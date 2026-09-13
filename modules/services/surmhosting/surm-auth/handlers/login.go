package handlers

import (
	"log/slog"
	"net/http"
	"net/url"
	"time"

	"github.com/surma/surm-auth/auth"
)

// handleLogin renders the login page. A missing app key renders the
// plain auth-host login; a known app key renders app-targeted copy.
func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}

	app := r.URL.Query().Get("app")
	redirect := r.URL.Query().Get("redirect")

	displayApp := ""
	allowedHosts := s.authHostList()
	if app != "" {
		appCfg, ok := s.deps.Config.Apps[app]
		if !ok {
			s.renderError(w, http.StatusNotFound, "Unknown application")
			return
		}
		displayApp = app
		allowedHosts = appCfg.Domains
	}

	// An invalid user-supplied redirect falls back to the landing page.
	redirect = s.validateRedirect(redirect, allowedHosts, "/")

	authURL := "/login/github?"
	params := url.Values{}
	if app != "" {
		params.Set("app", app)
	}
	params.Set("redirect", redirect)
	authURL += params.Encode()

	if err := s.tmpl.ExecuteTemplate(w, "login.html", map[string]any{
		"App":     displayApp,
		"AuthURL": authURL,
	}); err != nil {
		slog.Error("failed to render login template", "error", err)
	}
}

// handleLoginGitHub initiates OAuth: it signs the transaction state,
// binds a host-only transaction cookie, and redirects to the provider.
func (s *Server) handleLoginGitHub(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}

	provider, ok := s.deps.Providers["github"]
	if !ok {
		s.renderError(w, http.StatusInternalServerError, "No login provider configured")
		return
	}

	app := r.URL.Query().Get("app")
	allowedHosts := s.authHostList()
	if app != "" {
		appCfg, ok := s.deps.Config.Apps[app]
		if !ok {
			s.renderError(w, http.StatusNotFound, "Unknown application")
			return
		}
		allowedHosts = appCfg.Domains
	}

	redirect := s.validateRedirect(r.URL.Query().Get("redirect"), allowedHosts, "/")

	data, err := auth.NewStateData(provider.Name(), app, redirect, time.Now(), s.deps.Tx.TTL())
	if err != nil {
		slog.Error("failed to build state", "error", err)
		s.renderError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	if err := s.deps.Tx.Begin(data); err != nil {
		slog.Error("failed to record transaction", "error", err)
		s.renderError(w, http.StatusInternalServerError, "Too many pending logins; try again later")
		return
	}

	state, err := auth.EncodeState(data, s.deps.Secret)
	if err != nil {
		slog.Error("failed to encode state", "error", err)
		s.renderError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	// Host-only transaction cookie on the canonical auth host so it
	// reaches the fixed callback.
	http.SetCookie(w, &http.Cookie{
		Name:     txCookie,
		Value:    data.Nonce,
		Path:     "/",
		MaxAge:   int(s.deps.Tx.TTL().Seconds()),
		Secure:   s.deps.Config.Session.CookieSecure,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})

	slog.Info("initiating OAuth login", "provider", provider.Name(), "app", app)
	http.Redirect(w, r, provider.AuthURL(state), http.StatusFound)
}

func (s *Server) authHostList() []string {
	hosts := make([]string, 0, len(s.authHosts))
	for host := range s.authHosts {
		hosts = append(hosts, host)
	}
	return hosts
}
