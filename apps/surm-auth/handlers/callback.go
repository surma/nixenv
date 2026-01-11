package handlers

import (
	"html/template"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"

	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
)

// CallbackHandler handles the OAuth callback
func CallbackHandler(provider auth.Provider, sm *auth.Manager, cfg *config.Config, secret []byte) http.HandlerFunc {
	// Get template path from environment or use default
	templatePath := os.Getenv("SURM_AUTH_TEMPLATES")
	if templatePath == "" {
		templatePath = "./templates"
	}

	errorTmplPath := filepath.Join(templatePath, "error.html")
	errorTmpl := template.Must(template.ParseFiles(errorTmplPath))

	return func(w http.ResponseWriter, r *http.Request) {
		code := r.URL.Query().Get("code")
		state := r.URL.Query().Get("state")

		if code == "" || state == "" {
			slog.Error("callback missing parameters")
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		// Decode and verify state
		stateData, err := auth.DecodeState(state, secret)
		if err != nil {
			slog.Error("failed to decode state", "error", err)
			http.Error(w, "Invalid state", http.StatusBadRequest)
			return
		}

		app := stateData.App
		redirectURL := stateData.Redirect

		// Exchange code for user info
		user, err := provider.Exchange(code)
		if err != nil {
			slog.Error("failed to exchange code", "error", err)
			http.Error(w, "OAuth exchange failed", http.StatusInternalServerError)
			return
		}

		slog.Info("user authenticated via OAuth",
			"app", app,
			"user", user.Username)

		// Check if app exists
		appCfg, exists := cfg.Apps[app]
		if !exists {
			slog.Error("unknown app in callback", "app", app)
			renderError(w, errorTmpl, "Unknown application")
			return
		}

		// Check if user is in allowlist
		allowed := false
		for _, allowedUser := range appCfg.AllowedUsers {
			if allowedUser == user.Username {
				allowed = true
				break
			}
		}

		if !allowed {
			slog.Warn("user not in allowlist",
				"app", app,
				"user", user.Username)
			renderError(w, errorTmpl, "Access denied")
			return
		}

		// Create session cookie
		if err := sm.Create(w, user); err != nil {
			slog.Error("failed to create session", "error", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		slog.Info("session created, redirecting",
			"app", app,
			"user", user.Username,
			"redirect", redirectURL)

		// Redirect to original URL
		http.Redirect(w, r, redirectURL, http.StatusFound)
	}
}

func renderError(w http.ResponseWriter, tmpl *template.Template, message string) {
	data := map[string]string{
		"Error": message,
	}
	w.WriteHeader(http.StatusForbidden)
	if err := tmpl.Execute(w, data); err != nil {
		slog.Error("failed to render error template", "error", err)
	}
}
