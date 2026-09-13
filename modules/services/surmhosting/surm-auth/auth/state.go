package auth

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"sync"
	"time"
)

// statePurpose separates the OAuth state signing key from other uses
// of the cookie secret.
const statePurpose = "surm-auth:oauth-state:v2"

// DefaultTransactionTTL is the OAuth transaction lifetime.
const DefaultTransactionTTL = 10 * time.Minute

// DefaultTransactionLimit bounds the outstanding transaction map.
const DefaultTransactionLimit = 1024

// StateData contains the signed data carried in the OAuth state
// parameter.
type StateData struct {
	Provider  string `json:"provider"`
	App       string `json:"app,omitempty"`
	Redirect  string `json:"redirect"`
	Nonce     string `json:"nonce"`
	IssuedAt  int64  `json:"issued_at"`
	ExpiresAt int64  `json:"expires_at"`
}

// NewStateData builds state data with a cryptographically random
// 32-byte nonce and the given lifetime.
func NewStateData(provider, app, redirect string, now time.Time, ttl time.Duration) (StateData, error) {
	nonce, err := randomToken(32)
	if err != nil {
		return StateData{}, fmt.Errorf("failed to generate nonce: %w", err)
	}
	return StateData{
		Provider:  provider,
		App:       app,
		Redirect:  redirect,
		Nonce:     nonce,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
	}, nil
}

// EncodeState signs the state data with a purpose-derived HMAC key and
// returns a URL-safe token.
func EncodeState(data StateData, secret []byte) (string, error) {
	key := DerivePurposeKey(secret, statePurpose)
	return encodeSignedJSON(data, key)
}

// DecodeState verifies the state token signature and decodes the data.
func DecodeState(token string, secret []byte) (*StateData, error) {
	key := DerivePurposeKey(secret, statePurpose)

	var data StateData
	if err := decodeSignedJSON(token, key, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

// Validate checks the state data against the expected provider and the
// current time. Clock skew of up to one minute is tolerated for issued
// timestamps.
func (d *StateData) Validate(provider string, now time.Time) error {
	if d.Provider != provider {
		return fmt.Errorf("state provider mismatch")
	}
	if d.Nonce == "" {
		return fmt.Errorf("state nonce is empty")
	}
	if d.Redirect == "" {
		return fmt.Errorf("state redirect is empty")
	}
	if now.Unix() > d.ExpiresAt {
		return fmt.Errorf("state expired")
	}
	if now.Unix()+60 < d.IssuedAt {
		return fmt.Errorf("state issued in the future")
	}
	return nil
}

func encodeSignedJSON(v any, key []byte) (string, error) {
	return SignToken(v, key)
}

func decodeSignedJSON(token string, key []byte, v any) error {
	return VerifyToken(token, key, v)
}

// SignToken marshals v, signs it with the keyed HMAC, and returns a
// URL-safe "payload.signature" token.
func SignToken(v any, key []byte) (string, error) {
	payload, err := json.Marshal(v)
	if err != nil {
		return "", fmt.Errorf("failed to marshal signed payload: %w", err)
	}
	mac := hmac.New(sha256.New, key)
	mac.Write(payload)
	signature := mac.Sum(nil)

	value := base64.RawURLEncoding.EncodeToString(payload) + "." +
		base64.RawURLEncoding.EncodeToString(signature)
	return value, nil
}

// VerifyToken verifies a signed token's signature with constant-time
// comparison and decodes its payload strictly (unknown fields are
// rejected).
func VerifyToken(token string, key []byte, v any) error {
	payloadEnc, sigEnc, ok := bytes.Cut([]byte(token), []byte("."))
	if !ok {
		return fmt.Errorf("invalid signed token format")
	}
	payload, err := base64.RawURLEncoding.DecodeString(string(payloadEnc))
	if err != nil {
		return fmt.Errorf("invalid signed token payload: %w", err)
	}
	signature, err := base64.RawURLEncoding.DecodeString(string(sigEnc))
	if err != nil {
		return fmt.Errorf("invalid signed token signature: %w", err)
	}

	mac := hmac.New(sha256.New, key)
	mac.Write(payload)
	if !hmac.Equal(signature, mac.Sum(nil)) {
		return fmt.Errorf("signed token signature mismatch")
	}

	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("invalid signed token payload: %w", err)
	}
	return nil
}

// Transactions tracks outstanding OAuth transactions in a bounded
// in-memory map. A restart invalidates all pending transactions.
type Transactions struct {
	mu      sync.Mutex
	txs     map[string]txEntry
	max     int
	ttl     time.Duration
	nextSeq uint64
}

// txEntry pairs a transaction with its insertion sequence. Eviction
// uses the sequence, not IssuedAt, so same-second ties evict
// deterministically in insertion order.
type txEntry struct {
	data StateData
	seq  uint64
}

// NewTransactions creates a bounded transaction store.
func NewTransactions(max int, ttl time.Duration) *Transactions {
	if max <= 0 {
		max = DefaultTransactionLimit
	}
	if ttl <= 0 {
		ttl = DefaultTransactionTTL
	}
	return &Transactions{
		txs: make(map[string]txEntry),
		max: max,
		ttl: ttl,
	}
}

// Begin records a new outstanding transaction.
func (t *Transactions) Begin(data StateData) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.pruneLocked(time.Now())
	if _, exists := t.txs[data.Nonce]; exists {
		return fmt.Errorf("transaction nonce already outstanding")
	}
	if len(t.txs) >= t.max {
		t.evictOldestLocked()
	}
	t.nextSeq++
	t.txs[data.Nonce] = txEntry{data: data, seq: t.nextSeq}
	return nil
}

// evictOldestLocked removes the transaction inserted first. The
// insertion sequence makes the choice deterministic even when all
// outstanding transactions share one IssuedAt second.
func (t *Transactions) evictOldestLocked() {
	var oldestNonce string
	var oldestSeq uint64
	found := false
	for nonce, entry := range t.txs {
		if !found || entry.seq < oldestSeq {
			found = true
			oldestNonce = nonce
			oldestSeq = entry.seq
		}
	}
	if found {
		delete(t.txs, oldestNonce)
	}
}

// Consume atomically removes an outstanding transaction and returns
// its data. Replayed or expired transactions return an error.
func (t *Transactions) Consume(nonce string) (StateData, error) {
	t.mu.Lock()
	defer t.mu.Unlock()

	entry, ok := t.txs[nonce]
	if !ok {
		return StateData{}, fmt.Errorf("unknown or consumed transaction; start a new login attempt")
	}
	if time.Now().Unix() > entry.data.ExpiresAt {
		delete(t.txs, nonce)
		return StateData{}, fmt.Errorf("transaction expired; start a new login attempt")
	}
	delete(t.txs, nonce)
	return entry.data, nil
}

// Len returns the number of outstanding transactions.
func (t *Transactions) Len() int {
	t.mu.Lock()
	defer t.mu.Unlock()
	return len(t.txs)
}

// TTL returns the transaction lifetime.
func (t *Transactions) TTL() time.Duration {
	return t.ttl
}

func (t *Transactions) pruneLocked(now time.Time) {
	for nonce, entry := range t.txs {
		if now.Unix() > entry.data.ExpiresAt {
			delete(t.txs, nonce)
		}
	}
}
