package auth

import (
	"strconv"
	"strings"
	"testing"
	"time"
)

func stateForTest() StateData {
	return StateData{
		Provider:  "github",
		App:       "hedgedoc2",
		Redirect:  "https://hedgedoc.apps.surma.technology/",
		Nonce:     nonceForTest(),
		IssuedAt:  time.Now().Unix(),
		ExpiresAt: time.Now().Add(10 * time.Minute).Unix(),
	}
}

var nonceCounter int

// nonceForTest returns a unique nonce for each test state.
func nonceForTest() string {
	nonceCounter++
	return "nonce-" + time.Now().Format("150405.000000000") + "-" + strconv.Itoa(nonceCounter)
}

func TestStateRoundtrip(t *testing.T) {
	secret := []byte("state-secret")
	data := stateForTest()

	token, err := EncodeState(data, secret)
	if err != nil {
		t.Fatalf("EncodeState failed: %v", err)
	}
	decoded, err := DecodeState(token, secret)
	if err != nil {
		t.Fatalf("DecodeState failed: %v", err)
	}
	if *decoded != data {
		t.Errorf("decoded = %+v, want %+v", *decoded, data)
	}
	if err := decoded.Validate("github", time.Now()); err != nil {
		t.Errorf("valid state rejected: %v", err)
	}
}

func TestStateRejectsTampering(t *testing.T) {
	secret := []byte("state-secret")
	token, err := EncodeState(stateForTest(), secret)
	if err != nil {
		t.Fatal(err)
	}

	// Flip the payload characters.
	mutated := []byte(token)
	for i := 0; i < len(mutated); i++ {
		if mutated[i] == 'A' {
			mutated[i] = 'B'
			break
		}
	}
	if _, err := DecodeState(string(mutated), secret); err == nil {
		t.Fatal("tampered state accepted")
	}

	// A different secret must fail.
	if _, err := DecodeState(token, []byte("other-secret")); err == nil {
		t.Fatal("state signed with foreign secret accepted")
	}

	if _, err := DecodeState("garbage", secret); err == nil {
		t.Fatal("garbage state accepted")
	}
}

func TestStateKeyPurposeSeparation(t *testing.T) {
	// A token signed with the state key must not verify under the CSRF
	// key and vice versa.
	secret := []byte("shared")
	stateToken, err := EncodeState(stateForTest(), secret)
	if err != nil {
		t.Fatal(err)
	}

	csrfKey := DerivePurposeKey(secret, "surm-auth:csrf:v2")
	var payload map[string]any
	if err := VerifyToken(stateToken, csrfKey, &payload); err == nil {
		t.Fatal("state token verified under CSRF key")
	}
}

func TestStateValidate(t *testing.T) {
	now := time.Now()

	expired := stateForTest()
	expired.ExpiresAt = now.Add(-time.Second).Unix()
	if err := expired.Validate("github", now); err == nil {
		t.Error("expired state accepted")
	}

	future := stateForTest()
	future.IssuedAt = now.Add(2 * time.Hour).Unix()
	if err := future.Validate("github", now); err == nil {
		t.Error("state issued far in the future accepted")
	}

	wrongProvider := stateForTest()
	if err := wrongProvider.Validate("gitlab", now); err == nil {
		t.Error("provider mismatch accepted")
	}

	emptyNonce := stateForTest()
	emptyNonce.Nonce = ""
	if err := emptyNonce.Validate("github", now); err == nil {
		t.Error("empty nonce accepted")
	}

	emptyRedirect := stateForTest()
	emptyRedirect.Redirect = ""
	if err := emptyRedirect.Validate("github", now); err == nil {
		t.Error("empty redirect accepted")
	}
}

func TestStateNewNonceIsRandomAndLong(t *testing.T) {
	a, err := NewStateData("github", "app", "https://x/", time.Now(), time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	b, err := NewStateData("github", "app", "https://x/", time.Now(), time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if a.Nonce == b.Nonce {
		t.Fatal("nonce reuse across states")
	}
	// 32 bytes of entropy -> 64 hex characters.
	if len(a.Nonce) != 64 {
		t.Errorf("nonce length = %d, want 64 hex chars", len(a.Nonce))
	}
}

func TestTransactionsConsumeOnce(t *testing.T) {
	txs := NewTransactions(8, time.Minute)
	data := stateForTest()

	if err := txs.Begin(data); err != nil {
		t.Fatalf("Begin failed: %v", err)
	}
	if txs.Len() != 1 {
		t.Errorf("len = %d", txs.Len())
	}

	got, err := txs.Consume(data.Nonce)
	if err != nil {
		t.Fatalf("Consume failed: %v", err)
	}
	if got.App != data.App {
		t.Errorf("consumed data = %+v", got)
	}

	// Replay must fail.
	if _, err := txs.Consume(data.Nonce); err == nil {
		t.Fatal("replayed transaction accepted")
	}
}

func TestTransactionsCookieBinding(t *testing.T) {
	txs := NewTransactions(8, time.Minute)
	data := stateForTest()
	if err := txs.Begin(data); err != nil {
		t.Fatal(err)
	}

	// A different nonce (as from another browser) must not consume the
	// transaction.
	if _, err := txs.Consume("forged-nonce"); err == nil {
		t.Fatal("mismatched nonce consumed the transaction")
	}
	if txs.Len() != 1 {
		t.Error("transaction was removed by a mismatched nonce")
	}
}

func TestTransactionsExpiry(t *testing.T) {
	txs := NewTransactions(8, time.Minute)
	data := stateForTest()
	// The schema stores Unix seconds, so expire the transaction by
	// writing a past timestamp directly.
	data.ExpiresAt = time.Now().Unix() - 1
	if err := txs.Begin(data); err != nil {
		t.Fatal(err)
	}
	if _, err := txs.Consume(data.Nonce); err == nil {
		t.Fatal("expired transaction accepted")
	}
}

func TestTransactionsBounded(t *testing.T) {
	txs := NewTransactions(3, time.Minute)

	first := stateForTest()
	if err := txs.Begin(first); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 5; i++ {
		data := stateForTest()
		data.Nonce = strings.Repeat("x", 10) + string(rune('a'+i))
		if err := txs.Begin(data); err != nil {
			t.Fatalf("Begin %d failed: %v", i, err)
		}
	}

	if txs.Len() > 3 {
		t.Errorf("store exceeded its bound: %d", txs.Len())
	}
	// The oldest transaction must have been evicted.
	if _, err := txs.Consume(first.Nonce); err == nil {
		t.Error("evicted transaction still consumable")
	}
}

func TestTransactionsPrunesExpired(t *testing.T) {
	txs := NewTransactions(8, time.Minute)
	for i := 0; i < 3; i++ {
		data := stateForTest()
		data.ExpiresAt = time.Now().Unix() - 1
		if err := txs.Begin(data); err != nil {
			t.Fatal(err)
		}
	}
	next := stateForTest()
	if err := txs.Begin(next); err != nil {
		t.Fatalf("Begin after expiry failed: %v", err)
	}
	if txs.Len() != 1 {
		t.Errorf("expired transactions not pruned: %d outstanding", txs.Len())
	}
}
