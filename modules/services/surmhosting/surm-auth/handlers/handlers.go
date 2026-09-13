// Package handlers implements the surm-auth v2 HTTP surface: forward
// auth, login, callback, logout, and the server-rendered admin UI.
package handlers

import (
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"net/url"
	"path/filepath"
	"sort"
	"strings"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
	"github.com/surma/surm-auth/policy"
)

// txCookie is the host-only OAuth transaction cookie.
const txCookie = "surm_auth_tx"

// Deps wires the shared dependencies for all handlers.
type Deps struct {
	Config    *config.Config
	Secret    []byte
	Providers map[string]auth.Provider
	Sessions  *auth.Manager
	Tx        *auth.Transactions
	Policy    *policy.Store
	Audit     *audit.Logger
}

// Server holds the constructed handlers and parsed templates.
type Server struct {
	deps          Deps
	tmpl          *template.Template
	canonical     string
	canonicalHost string
	authHosts     map[string]bool
}

// New constructs the server and parses all templates once. A template
// error stops startup cleanly. Bootstrap-admin management lives in the
// policy store, which learns the managed set through its Bootstrap
// call.
func New(deps Deps, templateDir string) (*Server, error) {
	names := []string{"login.html", "error.html", "admin.html", "admin_app.html", "audit.html"}
	paths := make([]string, 0, len(names))
	for _, name := range names {
		paths = append(paths, filepath.Join(templateDir, name))
	}
	tmpl, err := template.ParseFiles(paths...)
	if err != nil {
		return nil, fmt.Errorf("failed to parse templates: %w", err)
	}

	base := strings.TrimSuffix(deps.Config.Server.BaseURL, "/")
	parsed, err := url.Parse(base)
	if err != nil {
		return nil, fmt.Errorf("invalid base URL: %w", err)
	}

	authHosts := make(map[string]bool, len(deps.Config.Server.AuthDomains))
	for _, d := range deps.Config.Server.AuthDomains {
		authHosts[strings.ToLower(d)] = true
	}

	return &Server{
		deps:          deps,
		tmpl:          tmpl,
		canonical:     base,
		canonicalHost: strings.ToLower(parsed.Host),
		authHosts:     authHosts,
	}, nil
}

// Register registers all routes on the mux.
func (s *Server) Register(mux *http.ServeMux) {
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/", s.handleRoot)
	mux.HandleFunc("/auth", s.handleAuth)
	mux.HandleFunc("/login", s.handleLogin)
	mux.HandleFunc("/login/github", s.handleLoginGitHub)
	mux.HandleFunc("/callback", s.handleCallback)
	mux.HandleFunc("/logout", s.handleLogout)
	mux.HandleFunc("/admin", s.handleAdmin)
	mux.HandleFunc("/admin/audit", s.handleAdminAudit)
	mux.HandleFunc("/admin/grants/delete", s.handleAdminGrantDelete)
	mux.HandleFunc("/admin/users/role", s.handleAdminRole)
	mux.HandleFunc("/admin/apps/", s.handleAdminApps)
}

// handleHealth reports readiness, including valid policy
// initialization.
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if !s.deps.Policy.Available() {
		http.Error(w, "Policy store unavailable", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "OK")
}

// handleRoot renders the safe auth landing page.
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}

	claims := s.session(r)
	isAdmin := false
	if claims != nil {
		var err error
		isAdmin, err = s.deps.Policy.IsAdmin(claims.Provider, claims.UID)
		if err != nil {
			slog.Warn("failed to check landing-page admin status", "subject", claims.SubjectID(), "error", err)
			isAdmin = false
		}
	}
	if err := s.tmpl.ExecuteTemplate(w, "login.html", map[string]any{
		"App":      "",
		"LoggedIn": claims != nil,
		"Username": usernameOrEmpty(claims),
		"IsAdmin":  isAdmin,
		"AuthURL":  "/login/github?redirect=%2F",
	}); err != nil {
		slog.Error("failed to render landing template", "error", err)
	}
}

func usernameOrEmpty(claims *auth.Claims) string {
	if claims == nil {
		return ""
	}
	if claims.Username != "" {
		return claims.Username
	}
	return claims.SubjectID()
}

// canonicalize redirects browser requests that arrive through an auth
// alias to the canonical auth host so host-only transaction cookies
// reach the fixed callback. Non-canonical, non-auth hosts fail closed.
// It reports whether the request may proceed.
func (s *Server) canonicalize(w http.ResponseWriter, r *http.Request) bool {
	host := normalizeHost(r.Host)
	if host == s.canonicalHost {
		return true
	}
	if s.authHosts[host] {
		if r.Method == http.MethodGet || r.Method == http.MethodHead {
			http.Redirect(w, r, s.canonical+r.URL.RequestURI(), http.StatusFound)
			return false
		}
		http.Error(w, "Cross-host mutations are not allowed", http.StatusForbidden)
		return false
	}
	http.NotFound(w, r)
	return false
}

// session validates the request's session cookie and returns nil when
// absent or invalid.
func (s *Server) session(r *http.Request) *auth.Claims {
	claims, err := s.deps.Sessions.Validate(r)
	if err != nil {
		return nil
	}
	return claims
}

// requireAdmin redirects anonymous requests to canonical login and
// rejects non-admin sessions with 403.
func (s *Server) requireAdmin(w http.ResponseWriter, r *http.Request) (*auth.Claims, bool) {
	claims := s.session(r)
	if claims == nil {
		http.Redirect(w, r, s.canonical+"/login?redirect="+url.QueryEscape(r.URL.RequestURI()), http.StatusFound)
		return nil, false
	}
	admin, err := s.deps.Policy.IsAdmin(claims.Provider, claims.UID)
	if err != nil {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return nil, false
	}
	if !admin {
		s.renderError(w, http.StatusForbidden, "Administrator access required")
		return nil, false
	}
	return claims, true
}

// validateRedirect validates a user-supplied return URL. Relative
// same-origin paths pass through. Absolute URLs must use HTTPS, the
// normal HTTPS port, and a host in the allowed set. Invalid input
// falls back to the canonical landing path.
func (s *Server) validateRedirect(input string, allowedHosts []string, fallback string) string {
	if input == "" {
		return fallback
	}
	if strings.ContainsAny(input, "\\\r\n\x00") {
		return fallback
	}
	if strings.HasPrefix(input, "/") && !strings.HasPrefix(input, "//") {
		return input
	}
	u, err := url.Parse(input)
	if err != nil {
		return fallback
	}
	if u.Scheme != "https" || u.User != nil || u.Host == "" {
		return fallback
	}
	if port := u.Port(); port != "" && port != "443" {
		return fallback
	}
	host := normalizeHost(u.Host)
	allowed := false
	for _, h := range allowedHosts {
		if normalizeHost(h) == host {
			allowed = true
			break
		}
	}
	if !allowed {
		return fallback
	}
	return u.String()
}

func normalizeHost(host string) string {
	return strings.ToLower(strings.TrimSuffix(strings.ToLower(host), ":443"))
}

func (s *Server) renderError(w http.ResponseWriter, status int, message string) {
	w.WriteHeader(status)
	if err := s.tmpl.ExecuteTemplate(w, "error.html", map[string]any{
		"Error": message,
	}); err != nil {
		slog.Error("failed to render error template", "error", err)
	}
}

func sortedKeys(m map[string]config.AppConf) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
