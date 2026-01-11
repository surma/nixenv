package handlers

import (
	"html/template"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"

	"github.com/surma/surm-auth/auth"
)

// LoginHandler handles the login page
func LoginHandler(provider auth.Provider, secret []byte) http.HandlerFunc {
	// Get template path from environment or use default
	templatePath := os.Getenv("SURM_AUTH_TEMPLATES")
	if templatePath == "" {
		templatePath = "./templates"
	}

	tmplPath := filepath.Join(templatePath, "login.html")
	tmpl := template.Must(template.ParseFiles(tmplPath))

	return func(w http.ResponseWriter, r *http.Request) {
		app := r.URL.Query().Get("app")
		redirect := r.URL.Query().Get("redirect")

		if app == "" || redirect == "" {
			slog.Error("login request missing parameters",
				"app", app,
				"redirect", redirect)
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		// Encode state with app and redirect URL
		state, err := auth.EncodeState(app, redirect, secret)
		if err != nil {
			slog.Error("failed to encode state", "error", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		// Get OAuth authorization URL
		authURL := provider.AuthURL(state)

		slog.Info("showing login page", "app", app)

		// Render login page
		data := map[string]string{
			"App":     app,
			"AuthURL": authURL,
		}

		if err := tmpl.Execute(w, data); err != nil {
			slog.Error("failed to render template", "error", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
		}
	}
}
