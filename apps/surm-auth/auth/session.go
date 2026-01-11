package auth

import (
	"fmt"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Manager handles session creation and validation using JWT cookies
type Manager struct {
	secret       []byte
	cookieName   string
	cookieDomain string
	cookieSecure bool
	duration     time.Duration
}

// Claims represents the JWT claims for a session
type Claims struct {
	Username string `json:"sub"`
	Email    string `json:"email"`
	Avatar   string `json:"avatar"`
	jwt.RegisteredClaims
}

// NewManager creates a new session manager
func NewManager(secret []byte, name, domain string, secure bool, duration time.Duration) *Manager {
	return &Manager{
		secret:       secret,
		cookieName:   name,
		cookieDomain: domain,
		cookieSecure: secure,
		duration:     duration,
	}
}

// Create creates a new session for the user and sets the cookie
func (m *Manager) Create(w http.ResponseWriter, user *User) error {
	now := time.Now()
	claims := &Claims{
		Username: user.Username,
		Email:    user.Email,
		Avatar:   user.Avatar,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.duration)),
			Issuer:    "surm-auth",
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

// Validate validates the session cookie and returns the claims
func (m *Manager) Validate(r *http.Request) (*Claims, error) {
	cookie, err := r.Cookie(m.cookieName)
	if err != nil {
		return nil, fmt.Errorf("no session cookie: %w", err)
	}

	token, err := jwt.ParseWithClaims(cookie.Value, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return m.secret, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, fmt.Errorf("invalid token")
}

// Clear clears the session cookie
func (m *Manager) Clear(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     m.cookieName,
		Value:    "",
		Path:     "/",
		Domain:   m.cookieDomain,
		MaxAge:   -1,
		Secure:   m.cookieSecure,
		HttpOnly: true,
	})
}
