package handlers

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
)

// handleCallback completes the OAuth transaction: it verifies the
// signed state, the browser-bound transaction cookie, consumes the
// transaction once, exchanges the code, upserts display data, checks
// the destination app's current policy, and issues the session.
func (s *Server) handleCallback(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}

	if r.URL.Query().Get("error") != "" {
		s.renderError(w, http.StatusForbidden, "Login failed: "+r.URL.Query().Get("error_description"))
		return
	}

	code := r.URL.Query().Get("code")
	state := r.URL.Query().Get("state")
	if code == "" || state == "" {
		s.renderError(w, http.StatusBadRequest, "Missing callback parameters")
		return
	}

	data, err := auth.DecodeState(state, s.deps.Secret)
	if err != nil {
		slog.Warn("callback state verification failed", "error", err)
		s.renderError(w, http.StatusBadRequest, "Invalid state; start a new login attempt")
		return
	}

	providerName := data.Provider
	if data.Nonce == "" || !s.knownProvider(providerName) {
		s.renderError(w, http.StatusBadRequest, "Invalid state; start a new login attempt")
		return
	}
	if err := data.Validate(providerName, time.Now()); err != nil {
		slog.Warn("callback state validation failed", "error", err)
		s.renderError(w, http.StatusBadRequest, "Expired state; start a new login attempt")
		return
	}

	cookie, err := r.Cookie(txCookie)
	if err != nil {
		s.renderError(w, http.StatusBadRequest, "Missing login transaction; start a new login attempt")
		return
	}
	if cookie.Value != data.Nonce {
		s.renderError(w, http.StatusBadRequest, "Login transaction does not match this browser; start a new login attempt")
		return
	}

	// Consume the transaction exactly once under the store lock.
	if _, err := s.deps.Tx.Consume(data.Nonce); err != nil {
		slog.Warn("callback transaction rejected", "error", err)
		s.clearTxCookie(w)
		s.renderError(w, http.StatusBadRequest, "Used or expired transaction; start a new login attempt")
		return
	}
	s.clearTxCookie(w)

	provider, ok := s.deps.Providers[providerName]
	if !ok {
		s.renderError(w, http.StatusBadRequest, "Unknown login provider")
		return
	}

	user, err := provider.Exchange(code)
	if err != nil {
		slog.Error("OAuth exchange failed", "provider", providerName, "error", err)
		s.renderError(w, http.StatusInternalServerError, "OAuth exchange failed")
		return
	}

	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}
	if err := s.deps.Policy.UpsertUser(user, user.Subject()); err != nil {
		slog.Error("failed to persist login display data", "error", err)
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}

	if data.App != "" {
		if done := s.authorizeCallbackApp(w, r, data.App, user); !done {
			return
		}
	}

	if err := s.deps.Sessions.Create(w, user); err != nil {
		slog.Error("failed to create session", "error", err)
		s.renderError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	s.auditEvent(audit.Event{
		Event:   audit.EventLoginSuccess,
		Actor:   user.Subject(),
		Subject: user.Subject(),
		App:     data.App,
	})

	slog.Info("login complete",
		"provider", user.Provider,
		"user", user.Username,
		"app", data.App,
		"redirect", data.Redirect)
	http.Redirect(w, r, data.Redirect, http.StatusFound)
}

// authorizeCallbackApp checks the destination app's current policy
// before a session is issued. It renders the response itself and
// returns false when the request must not proceed.
func (s *Server) authorizeCallbackApp(w http.ResponseWriter, r *http.Request, appKey string, user *auth.User) bool {
	appCfg, ok := s.deps.Config.Apps[appKey]
	if !ok {
		slog.Warn("callback for unknown app", "app", appKey)
		s.auditEvent(audit.Event{
			Event:   audit.EventLoginDenied,
			Actor:   user.Subject(),
			Subject: user.Subject(),
			App:     appKey,
			Detail:  "unknown app",
		})
		s.renderError(w, http.StatusNotFound, "Unknown application")
		return false
	}

	if appCfg.Mode == config.ModeAllowlist {
		granted, err := s.deps.Policy.HasAccess(appKey, user.Provider, user.ID)
		if err != nil {
			s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
			return false
		}
		if !granted {
			slog.Warn("login denied without grant", "app", appKey, "subject", user.Subject())
			s.auditEvent(audit.Event{
				Event:   audit.EventLoginDenied,
				Actor:   user.Subject(),
				Subject: user.Subject(),
				App:     appKey,
				Detail:  "no grant on allowlisted app",
			})
			s.renderError(w, http.StatusForbidden, "Access denied")
			return false
		}
	}

	return true
}

func (s *Server) clearTxCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     txCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		Secure:   s.deps.Config.Session.CookieSecure,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) knownProvider(name string) bool {
	_, ok := s.deps.Providers[name]
	return ok
}

func (s *Server) auditEvent(event audit.Event) {
	if err := s.deps.Audit.Record(event); err != nil {
		slog.Error("failed to write audit event", "error", err)
	}
}
