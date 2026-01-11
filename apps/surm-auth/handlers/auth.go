package handlers

import (
	"fmt"
	"log/slog"
	"net/http"
	"net/url"

	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
)

// AuthHandler handles the ForwardAuth endpoint
// This is called by Traefik to validate requests
func AuthHandler(cfg *config.Config, sm *auth.Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Get app name from query parameter
		app := r.URL.Query().Get("app")
		if app == "" {
			slog.Error("auth request missing app parameter")
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		// Build original URL from forwarded headers
		proto := r.Header.Get("X-Forwarded-Proto")
		if proto == "" {
			proto = "https"
		}
		host := r.Header.Get("X-Forwarded-Host")
		uri := r.Header.Get("X-Forwarded-Uri")
		if uri == "" {
			uri = "/"
		}
		originalURL := fmt.Sprintf("%s://%s%s", proto, host, uri)

		// Validate session cookie
		claims, err := sm.Validate(r)
		if err != nil {
			// No valid session - redirect to login
			loginURL := fmt.Sprintf("%s/login?app=%s&redirect=%s",
				cfg.Server.BaseURL, app, url.QueryEscape(originalURL))
			
			slog.Info("no valid session, redirecting to login",
				"app", app,
				"redirect", originalURL)
			
			http.Redirect(w, r, loginURL, http.StatusFound)
			return
		}

		// Check if app exists in config
		appCfg, exists := cfg.Apps[app]
		if !exists {
			slog.Error("unknown app", "app", app)
			http.Error(w, "Access denied", http.StatusForbidden)
			return
		}

		// Check if user is in allowlist
		allowed := false
		for _, allowedUser := range appCfg.AllowedUsers {
			if allowedUser == claims.Username {
				allowed = true
				break
			}
		}

		if !allowed {
			slog.Warn("user not in allowlist",
				"app", app,
				"user", claims.Username)
			http.Error(w, "Access denied", http.StatusForbidden)
			return
		}

		// User is authenticated and authorized
		slog.Info("auth success",
			"app", app,
			"user", claims.Username)

		w.Header().Set("X-Auth-Request-User", claims.Username)
		w.Header().Set("X-Auth-Request-Email", claims.Email)
		w.WriteHeader(http.StatusOK)
	}
}
