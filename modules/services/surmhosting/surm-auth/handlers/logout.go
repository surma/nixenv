package handlers

import (
	"html/template"
	"log/slog"
	"net/http"

	"github.com/surma/surm-auth/audit"
)

// logoutTmpl is the logout confirmation template. It is constructed
// once at handler construction, like the file-based template set.
var logoutTmpl = template.Must(template.New("logout").Parse(`<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Log out</title></head>
<body>
<h1>Log out</h1>
{{if .LoggedIn}}
<p>Log out of your surm-auth session?</p>
<form method="POST" action="/logout">
<input type="hidden" name="csrf_token" value="{{.CSRF}}">
<button type="submit">Log out</button>
</form>
{{else}}
<p>You are not logged in.</p>
<a href="/login">Log in</a>
{{end}}
<p><a href="/">Back to the start page</a></p>
</body>
</html>
`))

// handleLogout serves a GET confirmation page and clears the session
// on a CSRF-validated POST.
func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	if !s.canonicalize(w, r) {
		return
	}

	switch r.Method {
	case http.MethodGet:
		claims := s.session(r)
		csrf := ""
		if claims != nil {
			token, err := s.csrfToken(claims, "/logout")
			if err != nil {
				slog.Error("failed to issue CSRF token", "error", err)
			}
			csrf = token
		}
		logoutTmpl.Execute(w, map[string]any{
			"LoggedIn": claims != nil,
			"CSRF":     csrf,
		})

	case http.MethodPost:
		claims := s.session(r)
		if claims == nil {
			// Nothing to end; send the anonymous visitor home.
			http.Redirect(w, r, "/", http.StatusFound)
			return
		}
		if !s.requireCSRF(w, r, claims, "/logout") {
			return
		}

		s.deps.Sessions.Clear(w)
		s.auditEvent(audit.Event{
			Event:   audit.EventLogout,
			Actor:   claims.SubjectID(),
			Subject: claims.SubjectID(),
		})
		slog.Info("user logged out", "subject", claims.SubjectID())
		http.Redirect(w, r, "/", http.StatusFound)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}
