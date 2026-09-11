package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/surma/surm-auth/auth"
)

// csrfPurpose separates the CSRF signing key from other uses of the
// cookie secret.
const csrfPurpose = "surm-auth:csrf:v2"

// csrfLifetime is the CSRF token lifetime.
const csrfLifetime = time.Hour

// csrfPayload is the signed body of a CSRF token.
type csrfPayload struct {
	Sub    string `json:"sub"`
	JTI    string `json:"jti"`
	Method string `json:"method"`
	Action string `json:"action"`
	Expiry int64  `json:"expiry"`
}

// csrfToken signs a CSRF token bound to the session subject, session
// jti, method, action path, and a one-hour expiry.
func (s *Server) csrfToken(claims *auth.Claims, action string) (string, error) {
	if claims == nil || claims.Subject == "" || claims.ID == "" {
		return "", fmt.Errorf("CSRF tokens require a session with a subject and ID")
	}
	key := auth.DerivePurposeKey(s.deps.Secret, csrfPurpose)
	return auth.SignToken(csrfPayload{
		Sub:    claims.Subject,
		JTI:    claims.ID,
		Method: http.MethodPost,
		Action: action,
		Expiry: time.Now().Add(csrfLifetime).Unix(),
	}, key)
}

// checkCSRF validates the request's CSRF token and Origin header.
func (s *Server) checkCSRF(r *http.Request, claims *auth.Claims, action string) error {
	if origin := r.Header.Get("Origin"); origin != s.canonical {
		return fmt.Errorf("request Origin does not match the auth host")
	}
	if err := r.ParseForm(); err != nil {
		return fmt.Errorf("invalid form body: %w", err)
	}

	token := r.PostFormValue("csrf_token")
	if token == "" {
		return fmt.Errorf("missing CSRF token")
	}

	key := auth.DerivePurposeKey(s.deps.Secret, csrfPurpose)
	var payload csrfPayload
	if err := auth.VerifyToken(token, key, &payload); err != nil {
		return fmt.Errorf("invalid CSRF token: %w", err)
	}

	if payload.Expiry <= time.Now().Unix() {
		return fmt.Errorf("expired CSRF token")
	}
	// Tokens are minted for POST only, so a token can never match a
	// request with another method. Comparing against the actual method
	// also keeps non-POST requests out of form-parsing mutations.
	if payload.Method != http.MethodPost {
		return fmt.Errorf("CSRF token method mismatch")
	}
	if r.Method != payload.Method {
		return fmt.Errorf("CSRF token does not match the request method")
	}
	if payload.Action != action {
		return fmt.Errorf("CSRF token action mismatch")
	}
	if claims == nil || payload.Sub != claims.Subject {
		return fmt.Errorf("CSRF token subject mismatch")
	}
	if claims.ID == "" || payload.JTI != claims.ID {
		return fmt.Errorf("CSRF token session mismatch")
	}
	return nil
}

// requireCSRF validates the token and renders an error page when it
// fails. It reports whether the request may proceed.
func (s *Server) requireCSRF(w http.ResponseWriter, r *http.Request, claims *auth.Claims, action string) bool {
	if err := s.checkCSRF(r, claims, action); err != nil {
		s.renderError(w, http.StatusForbidden, "Invalid or missing CSRF token")
		return false
	}
	return true
}
