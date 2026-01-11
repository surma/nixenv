package auth

// Provider defines the interface for OAuth providers
// This allows for future extensibility (Google, OIDC, etc.)
type Provider interface {
	// Name returns the provider name (e.g., "github")
	Name() string

	// AuthURL returns the OAuth authorization URL with the given state
	AuthURL(state string) string

	// Exchange exchanges an authorization code for user information
	Exchange(code string) (*User, error)
}

// User represents an authenticated user
type User struct {
	ID       string
	Username string
	Email    string
	Avatar   string
}
