package handlers

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
	"github.com/surma/surm-auth/policy"
)

const (
	canonicalBase = "https://auth.surma.technology"
	cookieSecret  = "test-cookie-secret-0123456789abcdef0123456789"
)

// testConfig builds a valid v2 config for handler tests.
func testConfig(t *testing.T) *config.Config {
	t.Helper()
	raw := `
version: 2
server:
  address: "127.0.0.1:0"
  base_url: "https://auth.surma.technology"
  auth_domains:
    - "auth.surma.technology"
    - "auth.apps.surma.technology"
session:
  cookie_name: "_surm_auth2"
  cookie_domain: ".surma.technology"
  cookie_secret_file: "/tmp/cookie-secret"
  cookie_secure: true
  duration: "168h"
policy:
  file: "POLICY"
audit:
  file: "AUDIT"
providers:
  github:
    client_id_file: "/tmp/id"
    client_secret_file: "/tmp/secret"
bootstrap_admins:
  - provider: "github"
    id: "1000"
apps:
  testapp:
    mode: "allowlist"
    domains: ["testapp.apps.surma.technology", "testapp.surma.technology"]
    seed_users: []
  pubapp:
    mode: "public"
    domains: ["pubapp.apps.surma.technology"]
  intapp:
    mode: "internal"
    domains: []
  authapp:
    mode: "authenticated"
    domains: ["authapp.apps.surma.technology"]
`
	raw = strings.Replace(raw, "POLICY", filepath.Join(t.TempDir(), "policy.json"), 1)
	raw = strings.Replace(raw, "AUDIT", filepath.Join(t.TempDir(), "audit.log"), 1)

	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte(raw), 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("test config invalid: %v", err)
	}
	return cfg
}

// fixtureTemplates writes minimal templates matching the handler data
// contracts into a temp directory and returns its path.
func fixtureTemplates(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	files := map[string]string{
		"login.html":     `LOGIN{{if .App}}|{{.App}}{{end}}{{if .LoggedIn}}|LOGGEDIN|{{.Subject}}{{end}}|{{.AuthURL}}`,
		"error.html":     `ERROR|{{.Error}}`,
		"admin.html":     `ADMIN|APPS{{range .Apps}}|{{.Key}}:{{.Mode}}:{{.Grants}}{{end}}|USERS{{range .Users}}|{{.Subject}}:{{.Role}}{{if .Managed}}:managed{{end}}{{end}}|CSRF:{{.CSRF}}|EVENTS{{range .Events}}|{{.Event}}{{end}}`,
		"admin_app.html": `APP|{{.App.Key}}:{{.App.Mode}}:{{.App.Domains}}|FORM:{{.GrantForm}}|GRANTS{{range .Grants}}|{{.Subject}}{{end}}|CG:{{.CSRFGrant}}|CD:{{.CSRFDelete}}`,
		"audit.html":     `AUDIT{{range .Events}}|{{.Event}}:{{.Actor}}:{{.App}}{{end}}`,
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// fakeProvider implements auth.Provider without any network calls.
type fakeProvider struct {
	users       map[string]*auth.User
	exchangeErr error
	resolveErr  error
}

func newFakeProvider() *fakeProvider {
	return &fakeProvider{users: map[string]*auth.User{
		// The user an OAuth exchange returns.
		"surma": {Provider: "github", ID: "2000", Username: "surma", Email: "surma@example.com"},
		// Users resolvable by username.
		"alice": {Provider: "github", ID: "2001", Username: "alice", Email: "alice@example.com"},
		"bob":   {Provider: "github", ID: "2002", Username: "bob", Email: "bob@example.com"},
	}}
}

func (f *fakeProvider) Name() string { return "github" }
func (f *fakeProvider) AuthURL(state string) string {
	return "https://github.test/oauth?state=" + state
}
func (f *fakeProvider) Exchange(code string) (*auth.User, error) {
	if f.exchangeErr != nil {
		return nil, f.exchangeErr
	}
	if code == "good-code" {
		return f.users["surma"], nil
	}
	return nil, fmt.Errorf("bad code")
}
func (f *fakeProvider) ResolveUsername(login string) (*auth.User, error) {
	if f.resolveErr != nil {
		return nil, f.resolveErr
	}
	if user, ok := f.users[login]; ok {
		return user, nil
	}
	return nil, fmt.Errorf("unresolved username %q", login)
}

// newTestServerWithTemplates constructs a Server against the given
// template directory (used to exercise the real repository templates).
func newTestServerWithTemplates(t *testing.T, templateDir string) *Server {
	t.Helper()
	return newTestServerWithTemplatesDir(t, testConfig(t), newFakeProvider(), 0, templateDir)
}

// newTestServer constructs a Server with fake dependencies and the
// fixture template directory.
func newTestServer(t *testing.T, cfg *config.Config, provider auth.Provider, txTTL time.Duration) *Server {
	t.Helper()
	return newTestServerWithTemplatesDir(t, cfg, provider, txTTL, fixtureTemplates(t))
}

// newTestServerWithTemplatesDir constructs a Server with an explicit
// template directory.
func newTestServerWithTemplatesDir(t *testing.T, cfg *config.Config, provider auth.Provider, txTTL time.Duration, templateDir string) *Server {
	t.Helper()

	store, err := policy.Open(cfg.Policy.File)
	if err != nil {
		t.Fatal(err)
	}
	auditLog, err := audit.Open(cfg.Audit.File)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = auditLog.Close() })

	if err := store.Bootstrap([]policy.Admin{{Provider: "github", ID: "1000"}}, nil); err != nil {
		t.Fatal(err)
	}

	if txTTL <= 0 {
		txTTL = auth.DefaultTransactionTTL
	}
	server, err := New(Deps{
		Config: cfg,
		Secret: []byte(cookieSecret),
		Providers: map[string]auth.Provider{
			provider.Name(): provider,
		},
		Sessions: auth.NewManager([]byte(cookieSecret), cfg.Session.CookieName, cfg.Session.CookieDomain, cfg.Session.CookieSecure, time.Hour),
		Tx:       auth.NewTransactions(auth.DefaultTransactionLimit, txTTL),
		Policy:   store,
		Audit:    auditLog,
	}, templateDir)
	if err != nil {
		t.Fatalf("New failed: %v", err)
	}
	return server
}

// mintCookie creates a session cookie for the user.
func mintCookie(t *testing.T, server *Server, user *auth.User) *http.Cookie {
	t.Helper()
	recorder := httptest.NewRecorder()
	if err := server.deps.Sessions.Create(recorder, user); err != nil {
		t.Fatal(err)
	}
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatal("no session cookie created")
	}
	return cookies[0]
}

// sessionRequest builds a request on the canonical auth host with the
// session cookie attached.
func sessionRequest(method, target string, cookie *http.Cookie) *http.Request {
	r := httptest.NewRequest(method, canonicalBase+target, nil)
	r.Host = "auth.surma.technology"
	if cookie != nil {
		r.AddCookie(cookie)
	}
	return r
}

// aliasRequest builds a request on the auth alias host with the
// session cookie attached.
func aliasRequest(method, target string, cookie *http.Cookie) *http.Request {
	r := httptest.NewRequest(method, "https://auth.apps.surma.technology"+target, nil)
	r.Host = "auth.apps.surma.technology"
	if cookie != nil {
		r.AddCookie(cookie)
	}
	return r
}

// postForm attaches form values to a request as a POST body.
func postForm(r *http.Request, form url.Values) *http.Request {
	r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	r.PostForm = form
	return r
}

// get runs a request against the server and returns the recorder.
func get(server *Server, r *http.Request) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	mux := http.NewServeMux()
	server.Register(mux)
	mux.ServeHTTP(recorder, r)
	return recorder
}

// csrfFromAdmin extracts the CSRF token for an action from a rendered
// admin page.
func csrfFrom(t *testing.T, body, prefix string) string {
	t.Helper()
	for _, part := range strings.Split(body, "|") {
		if strings.HasPrefix(part, prefix) {
			return strings.TrimPrefix(part, prefix)
		}
	}
	t.Fatalf("no %q in body: %s", prefix, body)
	return ""
}

// decodeStateForTest decodes a signed state with the test secret.
func decodeStateForTest(token string) (*auth.StateData, error) {
	return auth.DecodeState(token, []byte(cookieSecret))
}

func adminUser() *auth.User {
	return &auth.User{Provider: "github", ID: "1000", Username: "boss", Email: "boss@example.com"}
}

func plainUser(id string) *auth.User {
	return &auth.User{Provider: "github", ID: id, Username: "user" + id, Email: "u" + id + "@example.com"}
}
