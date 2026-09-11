package handlers

import (
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/auth"
)

// adminSession returns a cookie for the bootstrap admin (github:1000).
func adminSession(t *testing.T, server *Server) *http.Cookie {
	t.Helper()
	return mintCookie(t, server, adminUser())
}

func TestAdminAnonymousRedirectsToLogin(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/admin", nil))
	if recorder.Code != 302 {
		t.Fatalf("anonymous /admin status = %d, want 302", recorder.Code)
	}
	location := recorder.Header().Get("Location")
	if location != canonicalBase+"/login?redirect=%2Fadmin" {
		t.Errorf("login redirect = %q", location)
	}
}

func TestAdminNonAdminForbidden(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	cookie := mintCookie(t, server, plainUser("2001"))
	recorder := get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	if recorder.Code != 403 {
		t.Errorf("non-admin /admin status = %d, want 403", recorder.Code)
	}

	recorder = get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	if recorder.Code != 403 {
		t.Errorf("non-admin app page status = %d, want 403", recorder.Code)
	}

	recorder = get(server, sessionRequest(http.MethodGet, "/admin/audit", cookie))
	if recorder.Code != 403 {
		t.Errorf("non-admin audit status = %d, want 403", recorder.Code)
	}
}

func TestAdminDashboardRenders(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", "alice", "admin"); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Policy.UpsertUser(plainUser("2001"), "self"); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Audit.Record(auditEventForTest("login_success", "github:2001")); err != nil {
		t.Fatal(err)
	}

	recorder := get(server, sessionRequest(http.MethodGet, "/admin", adminSession(t, server)))
	if recorder.Code != 200 {
		t.Fatalf("admin status = %d, body: %s", recorder.Code, recorder.Body.String())
	}
	body := recorder.Body.String()
	for _, want := range []string{
		"testapp:allowlist:1",
		"pubapp:public:0",
		"intapp:internal:0",
		"github:1000:admin:managed",
		"github:2001:user",
		"login_success",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("admin page lacks %q: %s", want, body)
		}
	}
}

func TestAdminAppPage(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", "alice", "admin"); err != nil {
		t.Fatal(err)
	}

	cookie := adminSession(t, server)
	recorder := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	if recorder.Code != 200 {
		t.Fatalf("app page status = %d", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, "testapp:allowlist") || !strings.Contains(body, "github:2001") {
		t.Errorf("app page content wrong: %s", body)
	}
	if !strings.Contains(body, "FORM:true") {
		t.Error("allowlisted app lacks a grant form")
	}
	csrfGrant := csrfFrom(t, body, "CG:")
	csrfDelete := csrfFrom(t, body, "CD:")
	if csrfGrant == "" || csrfDelete == "" {
		t.Error("app page lacks CSRF tokens")
	}

	// Public and internal apps show their mode without grant forms.
	for _, app := range []string{"pubapp", "intapp"} {
		recorder := get(server, sessionRequest(http.MethodGet, "/admin/apps/"+app, cookie))
		if recorder.Code != 200 {
			t.Fatalf("%s page status = %d", app, recorder.Code)
		}
		if strings.Contains(recorder.Body.String(), "FORM:true") {
			t.Errorf("%s page shows a grant form", app)
		}
	}

	// Unknown apps 404.
	recorder = get(server, sessionRequest(http.MethodGet, "/admin/apps/ghost", cookie))
	if recorder.Code != 404 {
		t.Errorf("unknown app status = %d, want 404", recorder.Code)
	}
}

func TestAdminGrantAdd(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	cookie := adminSession(t, server)

	// Fetch the page to get a bound CSRF token.
	page := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	csrf := csrfFrom(t, page.Body.String(), "CG:")

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("username", "alice")
	request := sessionRequest(http.MethodPost, "/admin/apps/testapp/grants", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form

	recorder := get(server, request)
	if recorder.Code != 303 {
		t.Fatalf("grant add status = %d, want 303; body: %s", recorder.Code, recorder.Body.String())
	}

	// The grant holds the stable ID, not the username.
	ok, err := server.deps.Policy.HasAccess("testapp", "github", "2001")
	if err != nil || !ok {
		t.Fatalf("stable-ID grant missing: %v, %v", ok, err)
	}
	snapshot := server.deps.Policy.Snapshot()
	for _, g := range snapshot.Grants["testapp"] {
		if g.ID != "2001" {
			t.Errorf("grant stored a non-stable identity: %+v", g)
		}
	}

	// A grant change was audited.
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "grant_added" || last.App != "testapp" || last.Subject != "github:2001" || last.Actor != "github:1000" {
		t.Errorf("last audit event = %+v", last)
	}
}

func TestAdminGrantAddUnresolvedUser(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	cookie := adminSession(t, server)

	page := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	csrf := csrfFrom(t, page.Body.String(), "CG:")

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("username", "ghost")
	request := sessionRequest(http.MethodPost, "/admin/apps/testapp/grants", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form

	recorder := get(server, request)
	if recorder.Code != 400 {
		t.Fatalf("unresolved user status = %d, want 400", recorder.Code)
	}
	snapshot := server.deps.Policy.Snapshot()
	if len(snapshot.Grants["testapp"]) != 0 {
		t.Error("a grant was created for an unresolved user")
	}
}

func TestAdminGrantDelete(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", "alice", "admin"); err != nil {
		t.Fatal(err)
	}
	cookie := adminSession(t, server)

	page := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	csrf := csrfFrom(t, page.Body.String(), "CD:")

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("app", "testapp")
	form.Set("provider", "github")
	form.Set("id", "2001")
	request := sessionRequest(http.MethodPost, "/admin/grants/delete", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form

	recorder := get(server, request)
	if recorder.Code != 303 {
		t.Fatalf("grant delete status = %d", recorder.Code)
	}
	ok, _ := server.deps.Policy.HasAccess("testapp", "github", "2001")
	if ok {
		t.Error("grant survived deletion")
	}
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "grant_removed" || last.App != "testapp" {
		t.Errorf("last audit event = %+v", last)
	}
}

// TestAdminMutationsRequirePOST covers PUT and PATCH against grant
// deletion and role changes. Only POST may reach these mutations,
// even with a valid admin, a matching Origin, and a POST-bound CSRF
// token.
func TestAdminMutationsRequirePOST(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", "alice", "admin"); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Policy.UpsertUser(plainUser("2001"), "self"); err != nil {
		t.Fatal(err)
	}
	cookie := adminSession(t, server)

	appPage := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	csrfDelete := csrfFrom(t, appPage.Body.String(), "CD:")
	adminPage := get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	csrfRole := csrfFrom(t, adminPage.Body.String(), "CSRF:")

	try := func(method, target, token string, form url.Values) int {
		form.Set("csrf_token", token)
		request := sessionRequest(method, target, cookie)
		request.Header.Set("Origin", canonicalBase)
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		request.PostForm = form
		return get(server, request).Code
	}

	for _, method := range []string{http.MethodPut, http.MethodPatch} {
		deleteForm := url.Values{"app": {"testapp"}, "provider": {"github"}, "id": {"2001"}}
		if code := try(method, "/admin/grants/delete", csrfDelete, deleteForm); code != 405 {
			t.Errorf("%s grant delete: status = %d, want 405", method, code)
		}
		roleForm := url.Values{"provider": {"github"}, "id": {"2001"}, "role": {"admin"}}
		if code := try(method, "/admin/users/role", csrfRole, roleForm); code != 405 {
			t.Errorf("%s role change: status = %d, want 405", method, code)
		}
	}

	// No mutation happened.
	ok, _ := server.deps.Policy.HasAccess("testapp", "github", "2001")
	if !ok {
		t.Error("a wrong-method request removed the grant")
	}
	admin, _ := server.deps.Policy.IsAdmin("github", "2001")
	if admin {
		t.Error("a wrong-method request changed the role")
	}
}

func TestAdminRoleChange(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.UpsertUser(plainUser("2001"), "self"); err != nil {
		t.Fatal(err)
	}
	cookie := adminSession(t, server)

	page := get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	csrf := csrfFrom(t, page.Body.String(), "CSRF:")

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("provider", "github")
	form.Set("id", "2001")
	form.Set("role", "admin")
	request := sessionRequest(http.MethodPost, "/admin/users/role", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form

	recorder := get(server, request)
	if recorder.Code != 303 {
		t.Fatalf("role change status = %d", recorder.Code)
	}
	admin, _ := server.deps.Policy.IsAdmin("github", "2001")
	if !admin {
		t.Error("role not changed")
	}
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "role_changed" || last.Subject != "github:2001" {
		t.Errorf("last audit event = %+v", last)
	}

	// Demoting the bootstrap admin is rejected.
	form.Set("id", "1000")
	form.Set("role", "user")
	request = sessionRequest(http.MethodPost, "/admin/users/role", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form
	recorder = get(server, request)
	if recorder.Code != 403 {
		t.Errorf("managed-admin demotion status = %d, want 403", recorder.Code)
	}
	admin, _ = server.deps.Policy.IsAdmin("github", "1000")
	if !admin {
		t.Error("bootstrap admin was demoted")
	}

	// Demoting the last admin is rejected (the bootstrap admin is
	// the only admin).
	form.Set("id", "1000")
	form.Set("role", "user")
	request = sessionRequest(http.MethodPost, "/admin/users/role", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form
	recorder = get(server, request)
	if recorder.Code != 403 {
		t.Errorf("last-admin demotion status = %d, want 403", recorder.Code)
	}
}

func TestAdminCSRFRejections(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	cookie := adminSession(t, server)

	page := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	csrf := csrfFrom(t, page.Body.String(), "CG:")

	post := func(target string, token, origin string) *httptestResponse {
		form := url.Values{}
		if token != "" {
			form.Set("csrf_token", token)
		}
		form.Set("username", "alice")
		request := sessionRequest(http.MethodPost, target, cookie)
		if origin != "" {
			request.Header.Set("Origin", origin)
		}
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		request.PostForm = form
		recorder := get(server, request)
		return &httptestResponse{recorder.Code, recorder.Body.String()}
	}

	// Missing token.
	if r := post("/admin/apps/testapp/grants", "", canonicalBase); r.code != 403 {
		t.Errorf("missing CSRF token status = %d, want 403", r.code)
	}
	// Forged signature.
	if r := post("/admin/apps/testapp/grants", csrf[:20]+"forged", canonicalBase); r.code != 403 {
		t.Errorf("forged CSRF token status = %d, want 403", r.code)
	}
	// Missing Origin.
	if r := post("/admin/apps/testapp/grants", csrf, ""); r.code != 403 {
		t.Errorf("missing Origin status = %d, want 403", r.code)
	}
	// Cross-origin POST.
	if r := post("/admin/apps/testapp/grants", csrf, "https://evil.example.com"); r.code != 403 {
		t.Errorf("cross-origin POST status = %d, want 403", r.code)
	}

	// Wrong-action token: a token for a different action path.
	page = get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	roleToken := csrfFrom(t, page.Body.String(), "CSRF:")
	if r := post("/admin/apps/testapp/grants", roleToken, canonicalBase); r.code != 403 {
		t.Errorf("wrong-action CSRF token status = %d, want 403", r.code)
	}

	// Cross-session token: same subject but a different session ID.
	otherSession := mintCookie(t, server, adminUser())
	if otherSession.Value == cookie.Value {
		t.Fatal("two sessions share one cookie value")
	}
	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("username", "alice")
	request := sessionRequest(http.MethodPost, "/admin/apps/testapp/grants", otherSession)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form
	recorder := get(server, request)
	if recorder.Code != 403 {
		t.Errorf("cross-session CSRF token status = %d, want 403", recorder.Code)
	}

	// Expired token.
	expired := issueExpiredCSRF(t, server, cookie, "/admin/apps/testapp/grants")
	if r := post("/admin/apps/testapp/grants", expired, canonicalBase); r.code != 403 {
		t.Errorf("expired CSRF token status = %d, want 403", r.code)
	}

	// GET mutations are not accepted.
	getter := sessionRequest(http.MethodGet, "/admin/apps/testapp/grants?username=alice", cookie)
	getter.Header.Set("Origin", canonicalBase)
	recorder = get(server, getter)
	if recorder.Code != 405 {
		t.Errorf("GET mutation status = %d, want 405", recorder.Code)
	}

	// No policy state was changed by the rejected attempts.
	snapshot := server.deps.Policy.Snapshot()
	if len(snapshot.Grants["testapp"]) != 0 {
		t.Errorf("a rejected mutation changed policy: %+v", snapshot.Grants["testapp"])
	}
}

// TestAdminFormsViaAuthAlias covers grant and role forms reached
// through the auth alias (auth.apps.surma.technology): the alias must
// redirect to the canonical host before rendering any form, the form
// submission succeeds on the canonical host, and a mutation that
// still arrives through the alias fails its Origin check.
func TestAdminFormsViaAuthAlias(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.UpsertUser(plainUser("2001"), "self"); err != nil {
		t.Fatal(err)
	}
	cookie := adminSession(t, server)

	// The app page and the dashboard redirect the alias to the
	// canonical host without rendering any form.
	for _, target := range []string{"/admin/apps/testapp", "/admin"} {
		recorder := get(server, aliasRequest(http.MethodGet, target, cookie))
		if recorder.Code != 302 {
			t.Fatalf("alias GET %s: status = %d, want 302", target, recorder.Code)
		}
		if got := recorder.Header().Get("Location"); got != canonicalBase+target {
			t.Errorf("alias GET %s redirect = %q, want %q", target, got, canonicalBase+target)
		}
		if strings.Contains(recorder.Body.String(), "csrf_token") {
			t.Errorf("alias GET %s rendered a form on the alias", target)
		}
	}

	// Grant form: starting through the alias, the canonical page
	// renders and the submission succeeds there.
	page := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	if page.Code != 200 {
		t.Fatalf("canonical app page status = %d", page.Code)
	}
	csrfGrant := csrfFrom(t, page.Body.String(), "CG:")
	grantPost := postForm(sessionRequest(http.MethodPost, "/admin/apps/testapp/grants", cookie),
		url.Values{"csrf_token": {csrfGrant}, "username": {"alice"}})
	grantPost.Header.Set("Origin", canonicalBase)
	recorder := get(server, grantPost)
	if recorder.Code != 303 {
		t.Fatalf("grant add after alias redirect: status = %d, body: %s", recorder.Code, recorder.Body.String())
	}
	if ok, _ := server.deps.Policy.HasAccess("testapp", "github", "2001"); !ok {
		t.Error("grant from the alias-driven flow missing")
	}

	// Role form: the same alias-start flow on the dashboard.
	dash := get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	if dash.Code != 200 {
		t.Fatalf("canonical dashboard status = %d", dash.Code)
	}
	csrfRole := csrfFrom(t, dash.Body.String(), "CSRF:")
	rolePost := postForm(sessionRequest(http.MethodPost, "/admin/users/role", cookie),
		url.Values{"csrf_token": {csrfRole}, "provider": {"github"}, "id": {"2001"}, "role": {"admin"}})
	rolePost.Header.Set("Origin", canonicalBase)
	recorder = get(server, rolePost)
	if recorder.Code != 303 {
		t.Fatalf("role change after alias redirect: status = %d", recorder.Code)
	}
	if admin, _ := server.deps.Policy.IsAdmin("github", "2001"); !admin {
		t.Error("role change from the alias-driven flow missing")
	}

	// A mutation submitted through the alias itself fails closed: its
	// Origin is the alias, never the canonical auth host. The fixed
	// GitHub callback host is unaffected.
	aliasPost := aliasRequest(http.MethodPost, "/admin/apps/testapp/grants", cookie)
	aliasPost.Header.Set("Origin", "https://auth.apps.surma.technology")
	recorder = get(server, postForm(aliasPost, url.Values{"csrf_token": {csrfGrant}, "username": {"bob"}}))
	if recorder.Code != 403 {
		t.Errorf("alias-host mutation status = %d, want 403", recorder.Code)
	}
	snapshot := server.deps.Policy.Snapshot()
	for _, g := range snapshot.Grants["testapp"] {
		if g.ID == "2002" {
			t.Error("an alias-host mutation created a grant")
		}
	}
}

// TestAllMutationsRejectWrongMethodAndBadCSRF runs the method and
// CSRF matrix over every mutating endpoint: grant add, grant delete,
// role change, and logout. A valid POST-bound token never authorizes
// another method, and every invalid token class is rejected with 403
// without a state change.
func TestAllMutationsRejectWrongMethodAndBadCSRF(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	if err := server.deps.Policy.UpsertUser(plainUser("2001"), "self"); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", "alice", "admin"); err != nil {
		t.Fatal(err)
	}
	cookie := adminSession(t, server)
	otherSession := mintCookie(t, server, adminUser())

	// Valid, action-bound tokens for each mutation.
	appPage := get(server, sessionRequest(http.MethodGet, "/admin/apps/testapp", cookie))
	dash := get(server, sessionRequest(http.MethodGet, "/admin", cookie))
	logoutPage := get(server, sessionRequest(http.MethodGet, "/logout", cookie))
	validTokens := map[string]string{
		"/admin/apps/testapp/grants": csrfFrom(t, appPage.Body.String(), "CG:"),
		"/admin/grants/delete":       csrfFrom(t, appPage.Body.String(), "CD:"),
		"/admin/users/role":          csrfFrom(t, dash.Body.String(), "CSRF:"),
		"/logout":                    csrfFromHTML(t, logoutPage.Body.String()),
	}
	actions := make([]string, 0, len(validTokens))
	for _, action := range []string{"/admin/apps/testapp/grants", "/admin/grants/delete", "/admin/users/role", "/logout"} {
		actions = append(actions, action)
	}

	// The form body of each mutation, with the given token.
	forms := map[string]func(string) url.Values{
		"/admin/apps/testapp/grants": func(token string) url.Values {
			return url.Values{"csrf_token": {token}, "username": {"bob"}}
		},
		"/admin/grants/delete": func(token string) url.Values {
			return url.Values{"csrf_token": {token}, "app": {"testapp"}, "provider": {"github"}, "id": {"2001"}}
		},
		"/admin/users/role": func(token string) url.Values {
			return url.Values{"csrf_token": {token}, "provider": {"github"}, "id": {"2001"}, "role": {"admin"}}
		},
		"/logout": func(token string) url.Values {
			return url.Values{"csrf_token": {token}}
		},
	}

	// Wrong methods never mutate, even with a valid POST-bound token.
	for _, action := range actions {
		for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodPatch} {
			if action == "/logout" && method == http.MethodGet {
				// GET /logout is the confirmation page only.
				recorder := get(server, sessionRequest(method, action, cookie))
				if recorder.Code != 200 {
					t.Errorf("GET %s: status = %d, want 200", action, recorder.Code)
				}
				if _, err := server.deps.Sessions.Validate(sessionRequest(http.MethodGet, "/", cookie)); err != nil {
					t.Errorf("GET %s ended the session: %v", action, err)
				}
				continue
			}
			request := postForm(sessionRequest(method, action, cookie), forms[action](validTokens[action]))
			request.Header.Set("Origin", canonicalBase)
			if recorder := get(server, request); recorder.Code != 405 {
				t.Errorf("%s %s: status = %d, want 405", method, action, recorder.Code)
			}
		}
	}

	// Invalid token classes on POST: missing, forged, expired,
	// wrong-action, and cross-session tokens all fail with 403.
	submit := func(action, token string, withCookie *http.Cookie) int {
		request := postForm(sessionRequest(http.MethodPost, action, withCookie), forms[action](token))
		request.Header.Set("Origin", canonicalBase)
		return get(server, request).Code
	}
	for i, action := range actions {
		otherAction := actions[(i+1)%len(actions)]
		cases := []struct {
			name  string
			token string
			sess  *http.Cookie
		}{
			{"missing token", "", cookie},
			{"forged token", validTokens[action][:20] + "forged", cookie},
			{"expired token", issueExpiredCSRF(t, server, cookie, action), cookie},
			{"wrong-action token", validTokens[otherAction], cookie},
			{"cross-session token", validTokens[action], otherSession},
		}
		for _, c := range cases {
			if code := submit(action, c.token, c.sess); code != 403 {
				t.Errorf("%s with %s: status = %d, want 403", action, c.name, code)
			}
		}
	}

	// No rejected request changed any state.
	ok, _ := server.deps.Policy.HasAccess("testapp", "github", "2001")
	if !ok {
		t.Error("a rejected mutation removed the grant")
	}
	admin, _ := server.deps.Policy.IsAdmin("github", "2001")
	if admin {
		t.Error("a rejected mutation granted the admin role")
	}
	snapshot := server.deps.Policy.Snapshot()
	if len(snapshot.Grants["testapp"]) != 1 {
		t.Errorf("a rejected mutation changed grants: %+v", snapshot.Grants["testapp"])
	}
	if _, err := server.deps.Sessions.Validate(sessionRequest(http.MethodGet, "/", cookie)); err != nil {
		t.Errorf("a rejected logout ended the session: %v", err)
	}
	if _, err := server.deps.Sessions.Validate(sessionRequest(http.MethodGet, "/", otherSession)); err != nil {
		t.Errorf("a rejected logout ended the other session: %v", err)
	}
}

func TestAdminAuditPage(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	for i := 0; i < 3; i++ {
		if err := server.deps.Audit.Record(auditEventForTest("login_success", "github:2001")); err != nil {
			t.Fatal(err)
		}
	}

	recorder := get(server, sessionRequest(http.MethodGet, "/admin/audit", adminSession(t, server)))
	if recorder.Code != 200 {
		t.Fatalf("audit page status = %d", recorder.Code)
	}
	body := recorder.Body.String()
	if got := strings.Count(body, "login_success"); got != 3 {
		t.Errorf("audit page shows %d events, want 3", got)
	}
}

func TestLogoutFlow(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	cookie := adminSession(t, server)

	// GET renders the confirmation page with a bound token.
	recorder := get(server, sessionRequest(http.MethodGet, "/logout", cookie))
	if recorder.Code != 200 {
		t.Fatalf("logout page status = %d", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, "csrf_token") {
		t.Fatal("logout page lacks a CSRF token")
	}
	csrf := csrfFromHTML(t, body)

	// POST clears the session.
	form := url.Values{}
	form.Set("csrf_token", csrf)
	request := sessionRequest(http.MethodPost, "/logout", cookie)
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.PostForm = form

	recorder = get(server, request)
	if recorder.Code != 302 {
		t.Fatalf("logout POST status = %d, want 302", recorder.Code)
	}
	raw := ""
	for _, c := range recorder.Header().Values("Set-Cookie") {
		if strings.HasPrefix(c, "_surm_auth2=") {
			raw = c
		}
	}
	if !strings.Contains(raw, "Max-Age=0") {
		t.Errorf("logout did not clear the session cookie: %q", raw)
	}
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "logout" || last.Subject != "github:1000" {
		t.Errorf("last audit event = %+v", last)
	}

	// POST without CSRF is rejected.
	request = sessionRequest(http.MethodPost, "/logout", mintCookie(t, server, adminUser()))
	request.Header.Set("Origin", canonicalBase)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	recorder = get(server, request)
	if recorder.Code != 403 {
		t.Errorf("logout without CSRF status = %d, want 403", recorder.Code)
	}
}

// --- helpers ---

// issueExpiredCSRF mints a correctly signed token for action whose
// expiry has passed.
func issueExpiredCSRF(t *testing.T, server *Server, cookie *http.Cookie, action string) string {
	t.Helper()
	request := sessionRequest(http.MethodGet, "/", cookie)
	claims, err := server.deps.Sessions.Validate(request)
	if err != nil {
		t.Fatal(err)
	}
	key := auth.DerivePurposeKey(server.deps.Secret, csrfPurpose)
	token, err := auth.SignToken(csrfPayload{
		Sub:    claims.Subject,
		JTI:    claims.ID,
		Method: http.MethodPost,
		Action: action,
		Expiry: time.Now().Add(-time.Minute).Unix(),
	}, key)
	if err != nil {
		t.Fatal(err)
	}
	return token
}

type httptestResponse struct {
	code int
	body string
}

func auditEventForTest(event, subject string) audit.Event {
	return audit.Event{
		Event:   event,
		Actor:   subject,
		Subject: subject,
		App:     "testapp",
	}
}

// csrfFromHTML extracts the csrf_token value from a rendered HTML
// form (used for the inline logout template).
func csrfFromHTML(t *testing.T, body string) string {
	t.Helper()
	re := regexp.MustCompile(`name="csrf_token" value="([^"]+)"`)
	match := re.FindStringSubmatch(body)
	if match == nil {
		t.Fatalf("no csrf_token in HTML: %s", body)
	}
	return match[1]
}
