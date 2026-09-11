package handlers

import (
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strings"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/config"
)

// appView is the rendered view of one logical app.
type appView struct {
	Key       string
	Mode      string
	Domains   string
	SeedUsers string
	Grants    int
}

// userView is the rendered view of one known user.
type userView struct {
	Subject  string
	Provider string
	ID       string
	Username string
	Role     string
	Managed  bool
}

// grantView is the rendered view of one grant.
type grantView struct {
	Subject  string
	Username string
	Provider string
	ID       string
}

// handleAdmin renders the admin dashboard: apps, users, roles, and
// recent audit events.
func (s *Server) handleAdmin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}
	claims, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}

	snapshot := s.deps.Policy.Snapshot()

	apps := make([]appView, 0, len(s.deps.Config.Apps))
	for _, key := range sortedKeys(s.deps.Config.Apps) {
		appCfg := s.deps.Config.Apps[key]
		apps = append(apps, appView{
			Key:       key,
			Mode:      appCfg.Mode,
			Domains:   strings.Join(appCfg.Domains, ", "),
			SeedUsers: strings.Join(appCfg.SeedUsers, ", "),
			Grants:    len(snapshot.Grants[key]),
		})
	}

	users := make([]userView, 0, len(snapshot.Users))
	for subject, user := range snapshot.Users {
		users = append(users, userView{
			Subject:  subject,
			Provider: user.Provider,
			ID:       user.ID,
			Username: user.Username,
			Role:     user.Role,
			Managed:  s.deps.Policy.IsManaged(user.Provider, user.ID),
		})
	}
	sort.Slice(users, func(i, j int) bool { return users[i].Subject < users[j].Subject })

	events, err := s.deps.Audit.Latest(25)
	if err != nil {
		slog.Error("failed to read audit events", "error", err)
	}

	csrf, err := s.csrfToken(claims, "/admin/users/role")
	if err != nil {
		slog.Error("failed to issue CSRF token", "error", err)
	}

	if err := s.tmpl.ExecuteTemplate(w, "admin.html", map[string]any{
		"Apps":   apps,
		"Users":  users,
		"Events": events,
		"CSRF":   csrf,
	}); err != nil {
		slog.Error("failed to render admin template", "error", err)
	}
}

// handleAdminApps dispatches the /admin/apps/ subtree.
func (s *Server) handleAdminApps(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/admin/apps/")
	switch parts := strings.Split(rest, "/"); {
	case len(parts) == 1 && parts[0] != "":
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.handleAdminApp(w, r, parts[0])
	case len(parts) == 2 && parts[1] == "grants":
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.handleAdminAppGrant(w, r, parts[0])
	default:
		http.NotFound(w, r)
	}
}

// handleAdminApp renders one app's Nix-owned topology and editable
// grants.
func (s *Server) handleAdminApp(w http.ResponseWriter, r *http.Request, name string) {
	claims, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}

	appCfg, ok := s.deps.Config.Apps[name]
	if !ok {
		http.NotFound(w, r)
		return
	}

	snapshot := s.deps.Policy.Snapshot()
	grants := make([]grantView, 0, len(snapshot.Grants[name]))
	for _, g := range snapshot.Grants[name] {
		grants = append(grants, grantView{
			Subject:  subjectKey(g.Provider, g.ID),
			Username: g.Username,
			Provider: g.Provider,
			ID:       g.ID,
		})
	}

	// Grant editing only applies to allowlisted apps; internal and
	// public apps show their explicit mode without grant-edit forms.
	grantForm := appCfg.Mode == config.ModeAllowlist

	csrfGrant, err := s.csrfToken(claims, "/admin/apps/"+name+"/grants")
	if err != nil {
		slog.Error("failed to issue CSRF token", "error", err)
	}
	csrfDelete, err := s.csrfToken(claims, "/admin/grants/delete")
	if err != nil {
		slog.Error("failed to issue CSRF token", "error", err)
	}

	if err := s.tmpl.ExecuteTemplate(w, "admin_app.html", map[string]any{
		"App": appView{
			Key:       name,
			Mode:      appCfg.Mode,
			Domains:   strings.Join(appCfg.Domains, ", "),
			SeedUsers: strings.Join(appCfg.SeedUsers, ", "),
			Grants:    len(grants),
		},
		"Grants":     grants,
		"GrantForm":  grantForm,
		"CSRFGrant":  csrfGrant,
		"CSRFDelete": csrfDelete,
	}); err != nil {
		slog.Error("failed to render app template", "error", err)
	}
}

// handleAdminAppGrant resolves a username and adds its stable-ID
// grant.
func (s *Server) handleAdminAppGrant(w http.ResponseWriter, r *http.Request, name string) {
	claims, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}

	appCfg, ok := s.deps.Config.Apps[name]
	if !ok {
		http.NotFound(w, r)
		return
	}
	if appCfg.Mode != config.ModeAllowlist {
		s.renderError(w, http.StatusForbidden, "Grants only apply to allowlisted apps")
		return
	}
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}
	if !s.requireCSRF(w, r, claims, "/admin/apps/"+name+"/grants") {
		return
	}

	login := r.PostFormValue("username")
	provider, ok := s.deps.Providers["github"]
	if !ok {
		s.renderError(w, http.StatusInternalServerError, "No login provider configured")
		return
	}
	user, err := provider.ResolveUsername(login)
	if err != nil {
		slog.Warn("grant rejected for unresolved user", "app", name, "error", err)
		s.renderError(w, http.StatusBadRequest, "Could not resolve that username; no grant was created")
		return
	}

	if err := s.deps.Policy.AddGrant(name, user.Provider, user.ID, user.Username, claims.SubjectID()); err != nil {
		slog.Error("failed to add grant", "app", name, "error", err)
		s.auditEvent(audit.Event{
			Event:  audit.EventPolicyWriteError,
			Actor:  claims.SubjectID(),
			App:    name,
			Detail: fmt.Sprintf("grant add failed: %v", err),
		})
		s.renderError(w, http.StatusServiceUnavailable, "Could not persist the grant")
		return
	}

	s.auditEvent(audit.Event{
		Event:   audit.EventGrantAdded,
		Actor:   claims.SubjectID(),
		Subject: user.Subject(),
		App:     name,
		Detail:  "username " + user.Username,
	})
	slog.Info("grant added", "app", name, "subject", user.Subject(), "actor", claims.SubjectID())
	http.Redirect(w, r, "/admin/apps/"+name, http.StatusSeeOther)
}

// handleAdminGrantDelete removes one grant.
func (s *Server) handleAdminGrantDelete(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}
	if !s.requireCSRF(w, r, claims, "/admin/grants/delete") {
		return
	}

	app := r.PostFormValue("app")
	providerName := r.PostFormValue("provider")
	id := r.PostFormValue("id")
	if app == "" || providerName == "" || id == "" {
		s.renderError(w, http.StatusBadRequest, "Missing grant identity")
		return
	}

	if err := s.deps.Policy.RemoveGrant(app, providerName, id, claims.SubjectID()); err != nil {
		slog.Error("failed to remove grant", "app", app, "error", err)
		s.auditEvent(audit.Event{
			Event:  audit.EventPolicyWriteError,
			Actor:  claims.SubjectID(),
			App:    app,
			Detail: fmt.Sprintf("grant removal failed: %v", err),
		})
		s.renderError(w, http.StatusServiceUnavailable, "Could not persist the grant removal")
		return
	}

	s.auditEvent(audit.Event{
		Event:   audit.EventGrantRemoved,
		Actor:   claims.SubjectID(),
		Subject: subjectKey(providerName, id),
		App:     app,
	})
	slog.Info("grant removed", "app", app, "subject", subjectKey(providerName, id), "actor", claims.SubjectID())
	if _, stillConfigured := s.deps.Config.Apps[app]; stillConfigured {
		http.Redirect(w, r, "/admin/apps/"+app, http.StatusSeeOther)
		return
	}
	http.Redirect(w, r, "/admin", http.StatusSeeOther)
}

// handleAdminRole changes one mutable role.
func (s *Server) handleAdminRole(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}
	if !s.requireCSRF(w, r, claims, "/admin/users/role") {
		return
	}

	providerName := r.PostFormValue("provider")
	id := r.PostFormValue("id")
	role := r.PostFormValue("role")
	if providerName == "" || id == "" {
		s.renderError(w, http.StatusBadRequest, "Missing user identity")
		return
	}

	if err := s.deps.Policy.SetRole(providerName, id, role, claims.SubjectID()); err != nil {
		slog.Warn("role change rejected", "subject", subjectKey(providerName, id), "error", err)
		s.renderError(w, http.StatusForbidden, "Role change rejected: "+err.Error())
		return
	}

	s.auditEvent(audit.Event{
		Event:   audit.EventRoleChanged,
		Actor:   claims.SubjectID(),
		Subject: subjectKey(providerName, id),
		Detail:  "new role " + role,
	})
	slog.Info("role changed", "subject", subjectKey(providerName, id), "role", role, "actor", claims.SubjectID())
	http.Redirect(w, r, "/admin", http.StatusSeeOther)
}

// handleAdminAudit renders the latest 200 audit events.
func (s *Server) handleAdminAudit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.canonicalize(w, r) {
		return
	}
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	events, err := s.deps.Audit.Latest(200)
	if err != nil {
		slog.Error("failed to read audit events", "error", err)
	}

	if err := s.tmpl.ExecuteTemplate(w, "audit.html", map[string]any{
		"Events": events,
	}); err != nil {
		slog.Error("failed to render audit template", "error", err)
	}
}

func subjectKey(provider, id string) string {
	return provider + ":" + id
}
