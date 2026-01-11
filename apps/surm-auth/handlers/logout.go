package handlers

import (
	"log/slog"
	"net/http"

	"github.com/surma/surm-auth/auth"
)

// LogoutHandler handles logout requests
func LogoutHandler(sm *auth.Manager, baseURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Clear the session cookie
		sm.Clear(w)

		slog.Info("user logged out")

		// Redirect to a simple logged out page or back to login
		http.Redirect(w, r, baseURL+"/", http.StatusFound)
	}
}
