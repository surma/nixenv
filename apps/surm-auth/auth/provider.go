package auth

import (
	"crypto/hmac"
	"crypto/sha256"
)

// Provider defines the interface for OAuth providers. User identity is
// stable per provider: the ID must never be derived from a username.
// This allows for future extensibility (Google, OIDC, etc.).
type Provider interface {
	// Name returns the provider name (e.g., "github").
	Name() string

	// AuthURL returns the OAuth authorization URL with the given state.
	AuthURL(state string) string

	// Exchange exchanges an authorization code for user information.
	Exchange(code string) (*User, error)

	// ResolveUsername resolves a provider username to the canonical
	// user, including the stable numeric ID.
	ResolveUsername(login string) (*User, error)
}

// User represents an authenticated provider user. Provider and ID form
// the stable identity; username, email, and avatar are mutable display
// data.
type User struct {
	Provider string
	ID       string
	Username string
	Email    string
	Avatar   string
}

// Subject returns the stable subject identifier "<provider>:<id>".
func (u *User) Subject() string {
	return u.Provider + ":" + u.ID
}

// DerivePurposeKey derives a purpose-separated HMAC key from a secret.
// Distinct purposes (OAuth state, CSRF) must never share a key.
func DerivePurposeKey(secret []byte, purpose string) []byte {
	h := hmac.New(sha256.New, secret)
	h.Write([]byte(purpose))
	return h.Sum(nil)
}
