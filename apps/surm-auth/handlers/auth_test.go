package handlers

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"

	"github.com/surma/surm-auth/auth"
)

func TestAuthMissingAppKey(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, forwardRequest(t, "/auth", nil))
	if recorder.Code != 404 {
		t.Errorf("missing app key: status = %d, want 404", recorder.Code)
	}

	recorder = get(server, forwardRequest(t, "/auth?app=&app=testapp", nil))
	if recorder.Code != 404 {
		t.Errorf("empty+present app keys: status = %d, want 404", recorder.Code)
	}

	recorder = get(server, forwardRequest(t, "/auth?app=testapp&app=testapp", nil))
	if recorder.Code != 404 {
		t.Errorf("duplicate app keys: status = %d, want 404", recorder.Code)
	}

	recorder = get(server, forwardRequest(t, "/auth?app=doesnotexist", nil))
	if recorder.Code != 404 {
		t.Errorf("unknown app key: status = %d, want 404", recorder.Code)
	}
}

func TestAuthInternalAppRejected(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	recorder := get(server, forwardRequest(t, "/auth?app=intapp", nil))
	if recorder.Code != 403 {
		t.Errorf("internal app: status = %d, want 403", recorder.Code)
	}
}

func TestAuthPublicAppPassesWithoutIdentityHeaders(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, forwardRequest(t, "/auth?app=pubapp", map[string]string{
		"X-Forwarded-Host": "pubapp.apps.surma.technology",
	}))
	if recorder.Code != 200 {
		t.Fatalf("public app: status = %d, want 200", recorder.Code)
	}
	for _, header := range []string{"X-Auth-Request-User", "X-Auth-Request-Email"} {
		if got := recorder.Header().Get(header); got != "" {
			t.Errorf("public app invented identity header %s = %q", header, got)
		}
	}
}

func TestAuthRestrictedWithoutSessionRedirectsToCanonicalLogin(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, forwardRequest(t, "/auth?app=testapp", map[string]string{
		"X-Forwarded-Proto": "https",
		"X-Forwarded-Host":  "testapp.apps.surma.technology",
		"X-Forwarded-Uri":   "/some/path?x=1",
	}))
	if recorder.Code != 302 {
		t.Fatalf("anonymous restricted request: status = %d, want 302", recorder.Code)
	}
	location, err := url.Parse(recorder.Header().Get("Location"))
	if err != nil {
		t.Fatalf("bad login location: %v", err)
	}
	if location.Host != "auth.surma.technology" || location.Path != "/login" {
		t.Errorf("login location = %q", location.String())
	}
	if location.Query().Get("app") != "testapp" {
		t.Errorf("login app = %q", location.Query().Get("app"))
	}
	if got := location.Query().Get("redirect"); got != "https://testapp.apps.surma.technology/some/path?x=1" {
		t.Errorf("login redirect = %q", got)
	}
}

func TestAuthMalformedReturnMetadata(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	cases := map[string]map[string]string{
		"cross-app host": {
			"X-Forwarded-Proto": "https",
			"X-Forwarded-Host":  "pubapp.apps.surma.technology",
			"X-Forwarded-Uri":   "/",
		},
		"external host": {
			"X-Forwarded-Proto": "https",
			"X-Forwarded-Host":  "evil.example.com",
			"X-Forwarded-Uri":   "/",
		},
		"http proto": {
			"X-Forwarded-Proto": "http",
			"X-Forwarded-Host":  "testapp.apps.surma.technology",
			"X-Forwarded-Uri":   "/",
		},
		"odd port": {
			"X-Forwarded-Proto": "https",
			"X-Forwarded-Host":  "testapp.apps.surma.technology:8443",
			"X-Forwarded-Uri":   "/",
		},
		"missing host": {
			"X-Forwarded-Proto": "https",
			"X-Forwarded-Host":  "",
			"X-Forwarded-Uri":   "/",
		},
	}
	for name, headers := range cases {
		recorder := get(server, forwardRequest(t, "/auth?app=testapp", headers))
		if recorder.Code != 400 {
			t.Errorf("%s: status = %d, want 400", name, recorder.Code)
		}
	}
}

// TestAuthValidSessionRejectsBadReturnMetadata covers the matrix for
// authenticated requests: malformed or cross-app return metadata must
// fail with 400 even when the session itself is authorized. Metadata
// never changes the policy selection.
func TestAuthValidSessionRejectsBadReturnMetadata(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	user := plainUser("2001")
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", user.Username, "admin"); err != nil {
		t.Fatal(err)
	}

	cases := map[string]map[string]string{
		"cross-app host": {"X-Forwarded-Host": "pubapp.apps.surma.technology"},
		"external host":  {"X-Forwarded-Host": "evil.example.com"},
		"http proto":     {"X-Forwarded-Proto": "http"},
		"missing host":   {"X-Forwarded-Host": ""},
	}
	for name, headers := range cases {
		recorder := get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, headers))
		if recorder.Code != 400 {
			t.Errorf("%s: status = %d, want 400", name, recorder.Code)
		}
	}

	// The same session with the app's own metadata still succeeds.
	recorder := get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, nil))
	if recorder.Code != 200 {
		t.Errorf("own metadata with session: status = %d, want 200", recorder.Code)
	}
}

// TestAuthPublicAppRejectsBadReturnMetadata covers the matrix for
// public apps: the authentication bypass never accepts malformed or
// cross-app return metadata.
func TestAuthPublicAppRejectsBadReturnMetadata(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	cases := map[string]map[string]string{
		"cross-app host": {"X-Forwarded-Host": "testapp.apps.surma.technology"},
		"external host":  {"X-Forwarded-Host": "evil.example.com"},
		"http proto":     {"X-Forwarded-Proto": "http"},
		"missing host":   {"X-Forwarded-Host": ""},
	}
	for name, headers := range cases {
		recorder := get(server, forwardRequest(t, "/auth?app=pubapp", headers))
		if recorder.Code != 400 {
			t.Errorf("%s: status = %d, want 400", name, recorder.Code)
		}
	}

	// The public app's own metadata still yields 200 without identity
	// headers.
	recorder := get(server, forwardRequest(t, "/auth?app=pubapp", map[string]string{
		"X-Forwarded-Host": "pubapp.apps.surma.technology",
	}))
	if recorder.Code != 200 {
		t.Fatalf("public app with own metadata: status = %d, want 200", recorder.Code)
	}
	for _, header := range []string{"X-Auth-Request-User", "X-Auth-Request-Email"} {
		if got := recorder.Header().Get(header); got != "" {
			t.Errorf("public app invented identity header %s = %q", header, got)
		}
	}
}

func TestAuthAllowlistGrantMatrix(t *testing.T) {
	cfg := testConfig(t)
	server := newTestServer(t, cfg, newFakeProvider(), 0)
	user := plainUser("2001")

	// Without a grant: 403 plus an audit event.
	recorder := get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, nil))
	if recorder.Code != 403 {
		t.Fatalf("allowlist without grant: status = %d, want 403", recorder.Code)
	}
	events, err := server.deps.Audit.Latest(200)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, e := range events {
		if e.Event == "access_denied" && e.App == "testapp" && e.Subject == "github:2001" {
			found = true
		}
	}
	if !found {
		t.Error("no access_denied audit event for the allowlist rejection")
	}

	// The current policy applies even for an old session cookie: grant
	// now and the same cookie must pass without a new login.
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", user.Username, "admin"); err != nil {
		t.Fatal(err)
	}
	recorder = get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, nil))
	if recorder.Code != 200 {
		t.Fatalf("allowlist with grant: status = %d, want 200", recorder.Code)
	}
	if got := recorder.Header().Get("X-Auth-Request-User"); got != user.Username {
		t.Errorf("X-Auth-Request-User = %q", got)
	}
	if got := recorder.Header().Get("X-Auth-Request-Email"); got != user.Email {
		t.Errorf("X-Auth-Request-Email = %q", got)
	}

	// Revoke without a new session: the same cookie must now fail.
	if err := server.deps.Policy.RemoveGrant("testapp", "github", "2001", "admin"); err != nil {
		t.Fatal(err)
	}
	recorder = get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, nil))
	if recorder.Code != 403 {
		t.Errorf("allowlist after revocation: status = %d, want 403", recorder.Code)
	}
}

func TestAuthAdminRoleGrantsAccess(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	recorder := get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", adminUser(), nil))
	if recorder.Code != 200 {
		t.Fatalf("admin on allowlisted app: status = %d, want 200", recorder.Code)
	}
}

func TestAuthAuthenticatedMode(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	headers := map[string]string{
		"X-Forwarded-Host": "authapp.apps.surma.technology",
	}

	recorder := get(server, forwardRequest(t, "/auth?app=authapp", headers))
	if recorder.Code != 302 {
		t.Errorf("authenticated app without session: status = %d, want 302", recorder.Code)
	}

	recorder = get(server, forwardRequestWithSession(t, server, "/auth?app=authapp", plainUser("2001"), headers))
	if recorder.Code != 200 {
		t.Errorf("authenticated app with session: status = %d, want 200", recorder.Code)
	}
	if got := recorder.Header().Get("X-Auth-Request-User"); got == "" {
		t.Error("authenticated app did not set identity headers")
	}
}

func TestAuthPolicyUnavailable(t *testing.T) {
	cfg := testConfig(t)
	server := newTestServer(t, cfg, newFakeProvider(), 0)

	// Corrupt the on-disk policy and reload: the store becomes
	// unavailable.
	if err := writeCorruptPolicy(t, cfg.Policy.File); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Policy.Reload(); err == nil {
		t.Fatal("corrupt reload succeeded")
	}

	recorder := get(server, forwardRequest(t, "/auth?app=testapp", nil))
	if recorder.Code != 503 {
		t.Errorf("restricted app with unavailable policy: status = %d, want 503", recorder.Code)
	}

	// Public apps must still pass during a policy outage when their
	// own return metadata is valid.
	recorder = get(server, forwardRequest(t, "/auth?app=pubapp", map[string]string{
		"X-Forwarded-Host": "pubapp.apps.surma.technology",
	}))
	if recorder.Code != 200 {
		t.Errorf("public app during policy outage: status = %d, want 200", recorder.Code)
	}
}

// TestAuthSpoofedForwardedHeadersDoNotSelectPolicy mirrors the
// spoofed-header acceptance test: forwarded headers naming another app
// must never change which policy the fixed app key enforces.
func TestAuthSpoofedForwardedHeadersDoNotSelectPolicy(t *testing.T) {
	cfg := testConfig(t)
	server := newTestServer(t, cfg, newFakeProvider(), 0)
	user := plainUser("2001")

	// The user holds a grant on testapp only. The spoofed headers name
	// the public app; the fixed app key must still enforce testapp.
	if err := server.deps.Policy.AddGrant("testapp", "github", "2001", user.Username, "admin"); err != nil {
		t.Fatal(err)
	}
	headers := map[string]string{
		"X-Forwarded-Host": "pubapp.apps.surma.technology",
		"X-Forwarded-Uri":  "/",
	}

	// Without a session the fixed app key still redirects to login for
	// testapp; the spoofed host never relaxes the policy.
	recorder := get(server, forwardRequest(t, "/auth?app=testapp", headers))
	if recorder.Code != 400 {
		t.Errorf("spoofed cross-app metadata: status = %d, want 400", recorder.Code)
	}

	// With a valid session for a testapp grantee, cross-app metadata
	// still fails with 400: a successful response requires return
	// metadata that belongs to the selected app. The fixed app key
	// remains the only policy selector.
	recorder = get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", user, headers))
	if recorder.Code != 400 {
		t.Errorf("spoofed headers with a valid grantee session: status = %d, want 400", recorder.Code)
	}

	// A grant-less user cannot bypass testapp by spoofing the public
	// app's host; the malformed metadata fails first.
	outsider := plainUser("2002")
	recorder = get(server, forwardRequestWithSession(t, server, "/auth?app=testapp", outsider, headers))
	if recorder.Code != 400 {
		t.Errorf("grant-less user with spoofed headers: status = %d, want 400", recorder.Code)
	}

	// A grant on one app key never leaks into another.
	ok, err := server.deps.Policy.HasAccess("pubapp", "github", "2001")
	if err != nil || ok {
		t.Errorf("testapp grant leaked into the public app: %v, %v", ok, err)
	}
}

func TestAuthMethodNotAllowed(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)
	r := forwardRequest(t, "/auth?app=pubapp", nil)
	r.Method = "POST"
	recorder := get(server, r)
	if recorder.Code != 405 {
		t.Errorf("POST /auth: status = %d, want 405", recorder.Code)
	}
}

func TestValidateRedirectRules(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	allowed := []string{"testapp.apps.surma.technology", "testapp.surma.technology"}
	cases := []struct {
		input    string
		expected string
	}{
		{"", "/"},
		{"/admin", "/admin"},
		{"/some/path?x=1", "/some/path?x=1"},
		{"https://testapp.apps.surma.technology/p", "https://testapp.apps.surma.technology/p"},
		{"https://testapp.apps.surma.technology:443/p", "https://testapp.apps.surma.technology:443/p"},
		{"http://testapp.apps.surma.technology/p", "/"},
		{"https://evil.example.com/p", "/"},
		{"https://user:pw@testapp.apps.surma.technology/p", "/"},
		{"//evil.example.com/p", "/"},
		{"https://testapp.apps.surma.technology:8443/p", "/"},
		{"ftp://testapp.apps.surma.technology/p", "/"},
	}
	for _, c := range cases {
		got := server.validateRedirect(c.input, allowed, "/")
		if got != c.expected {
			t.Errorf("validateRedirect(%q) = %q, want %q", c.input, got, c.expected)
		}
	}
}

// --- shared request builders ---

// forwardRequest builds a Traefik-style forward-auth request: it goes
// to the middleware address, carries forwarded metadata, and never
// has the client's Host.
func forwardRequest(t *testing.T, target string, headers map[string]string) *http.Request {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, "http://10.202.0.2:8080"+target, nil)
	r.Header.Set("X-Forwarded-Proto", "https")
	r.Header.Set("X-Forwarded-Host", "testapp.apps.surma.technology")
	r.Header.Set("X-Forwarded-Uri", "/")
	for k, v := range headers {
		r.Header.Set(k, v)
	}
	return r
}

// forwardRequestWithSession attaches a session cookie for the user.
func forwardRequestWithSession(t *testing.T, server *Server, target string, user *auth.User, headers map[string]string) *http.Request {
	t.Helper()
	r := forwardRequest(t, target, headers)
	r.AddCookie(mintCookie(t, server, user))
	return r
}

// writeCorruptPolicy replaces the policy file with garbage.
func writeCorruptPolicy(t *testing.T, path string) error {
	t.Helper()
	return os.WriteFile(path, []byte(`{corrupt`), 0600)
}

func TestCanonicalizeRedirectsAlias(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	r := httptest.NewRequest("GET", "https://auth.apps.surma.technology/login", nil)
	r.Host = "auth.apps.surma.technology"
	recorder := get(server, r)
	if recorder.Code != 302 {
		t.Fatalf("alias request: status = %d, want 302", recorder.Code)
	}
	if !strings.HasPrefix(recorder.Header().Get("Location"), canonicalBase+"/login") {
		t.Errorf("alias redirect = %q", recorder.Header().Get("Location"))
	}

	// An unrelated host fails closed.
	r = httptest.NewRequest("GET", "https://evil.example.com/login", nil)
	r.Host = "evil.example.com"
	recorder = get(server, r)
	if recorder.Code != 404 {
		t.Errorf("unrelated host: status = %d, want 404", recorder.Code)
	}
}
