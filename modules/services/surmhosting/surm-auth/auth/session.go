package auth

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// sessionIssuer is the required JWT issuer.
const sessionIssuer = "surm-auth"

// Manager handles v2 session creation and validation using HS256 JWT
// cookies with stable provider-ID subjects.
type Manager struct {
	secret       []byte
	cookieName   string
	cookieDomain string
	cookieSecure bool
	duration     time.Duration
}

// Claims represents the JWT claims for a v2 session. The subject is
// always "<provider>:<uid>"; display fields are mutable data only.
type Claims struct {
	Provider string `json:"provider"`
	UID      string `json:"uid"`
	Username string `json:"username"`
	Email    string `json:"email,omitempty"`
	Avatar   string `json:"avatar,omitempty"`
	jwt.RegisteredClaims
}

// NewManager creates a new session manager.
func NewManager(secret []byte, name, domain string, secure bool, duration time.Duration) *Manager {
	return &Manager{
		secret:       secret,
		cookieName:   name,
		cookieDomain: domain,
		cookieSecure: secure,
		duration:     duration,
	}
}

// SubjectID returns the stable subject "<provider>:<uid>".
func (c *Claims) SubjectID() string {
	return c.Provider + ":" + c.UID
}

// Create creates a new session for the user and sets the session
// cookie.
func (m *Manager) Create(w http.ResponseWriter, user *User) error {
	if user == nil || user.Provider == "" || user.ID == "" {
		return fmt.Errorf("session user requires a stable provider and ID")
	}

	now := time.Now()
	jti, err := randomToken(16)
	if err != nil {
		return fmt.Errorf("failed to generate session ID: %w", err)
	}

	claims := &Claims{
		Provider: user.Provider,
		UID:      user.ID,
		Username: user.Username,
		Email:    user.Email,
		Avatar:   user.Avatar,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        jti,
			Subject:   user.Subject(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.duration)),
			Issuer:    sessionIssuer,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(m.secret)
	if err != nil {
		return fmt.Errorf("failed to sign token: %w", err)
	}

	http.SetCookie(w, &http.Cookie{
		Name:     m.cookieName,
		Value:    tokenString,
		Path:     "/",
		Domain:   m.cookieDomain,
		Expires:  now.Add(m.duration),
		Secure:   m.cookieSecure,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})

	return nil
}

// Validate validates the session cookie and returns the claims. It
// requires HS256 specifically, the expected issuer, an expiration, and
// a matching stable subject. The old username-only shape is rejected.
func (m *Manager) Validate(r *http.Request) (*Claims, error) {
	cookie, err := r.Cookie(m.cookieName)
	if err != nil {
		return nil, fmt.Errorf("no session cookie: %w", err)
	}

	token, err := jwt.ParseWithClaims(cookie.Value, &Claims{}, func(token *jwt.Token) (any, error) {
		return m.secret, nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(sessionIssuer),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, fmt.Errorf("invalid session token: %w", err)
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid session token")
	}
	if claims.Provider == "" || claims.UID == "" {
		return nil, fmt.Errorf("session token lacks stable provider identity")
	}
	if claims.Subject != claims.Provider+":"+claims.UID {
		return nil, fmt.Errorf("session token subject does not match its identity")
	}

	return claims, nil
}

// Clear clears the session cookie with matching domain and path.
func (m *Manager) Clear(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     m.cookieName,
		Value:    "",
		Path:     "/",
		Domain:   m.cookieDomain,
		MaxAge:   -1,
		Secure:   m.cookieSecure,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

// randomToken returns a cryptographically random hex string with
// nBytes of entropy.
func randomToken(nBytes int) (string, error) {
	buf := make([]byte, nBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
