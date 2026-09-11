//go:build surm_auth_e2e

// Package main end-to-end test for the packaged binary. The build tag
// keeps the process test out of the ordinary unit suite; the flake
// check checks.*.surm-auth-e2e compiles this file with
// SURM_AUTH_BIN pointing at the wrapped nix package. The test fails
// instead of skipping when the binary is absent.
package main

// TestPackagedServer starts the real packaged surm-auth binary
// outside the source tree and drives the complete browser-like OAuth
// flow against a fully mocked GitHub provider on the loopback
// interface: forward-auth blocking, login redirect, mocked code
// exchange, real session issuance, grant enforcement, and public and
// internal app behavior. No request leaves the machine and no test
// JWT is minted; every session comes from the real binary.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// Synthetic credentials and stable identities for the mocked provider.
const (
	mockClientID     = "synthetic-client-id"
	mockClientSecret = "synthetic-client-secret"
	canonicalHost    = "auth.surma.technology"
	sessionCookie    = "_surm_auth2"
)

var (
	userAdmin    = mockUser{id: "1000", login: "boss"}
	userGrants   = mockUser{id: "2000", login: "surma"}
	userDenied   = mockUser{id: "2999", login: "nobody"}
	usersByLogin = map[string]mockUser{
		userAdmin.login:  userAdmin,
		userGrants.login: userGrants,
		userDenied.login: userDenied,
	}
)

// mockUser is one stable identity the mocked provider authenticates.
type mockUser struct {
	id    string
	login string
}

// mockProvider implements the four GitHub endpoints the real binary
// consumes: authorization, token exchange, the authenticated user,
// and the users lookup API used for seed resolution.
type mockProvider struct {
	mu     sync.Mutex
	asUser mockUser
	codes  map[string]mockUser
	tokens map[string]mockUser
}

func newMockProvider() *mockProvider {
	return &mockProvider{
		asUser: userGrants,
		codes:  map[string]mockUser{},
		tokens: map[string]mockUser{},
	}
}

// loginAs selects the identity the authorization endpoint signs in.
func (m *mockProvider) loginAs(user mockUser) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.asUser = user
}

func (m *mockProvider) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/authorize":
		m.handleAuthorize(w, r)
	case r.URL.Path == "/token":
		m.handleToken(w, r)
	case r.URL.Path == "/user":
		m.handleUser(w, r)
	case strings.HasPrefix(r.URL.Path, "/users/"):
		m.handleUserLookup(w, r)
	default:
		http.NotFound(w, r)
	}
}

// handleAuthorize acts like the provider consent page: it issues a
// code for the selected identity and redirects back to the real
// binary's callback URL.
func (m *mockProvider) handleAuthorize(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("client_id") != mockClientID {
		http.Error(w, "unknown client", http.StatusBadRequest)
		return
	}
	redirect, err := url.Parse(r.URL.Query().Get("redirect_uri"))
	if err != nil || redirect.Scheme == "" || redirect.Host == "" {
		http.Error(w, "bad redirect_uri", http.StatusBadRequest)
		return
	}
	m.mu.Lock()
	user := m.asUser
	code := "code-" + user.login
	m.codes[code] = user
	m.mu.Unlock()

	query := redirect.Query()
	query.Set("code", code)
	query.Set("state", r.URL.Query().Get("state"))
	redirect.RawQuery = query.Encode()
	http.Redirect(w, r, redirect.String(), http.StatusFound)
}

// handleToken exchanges a code for an access token, mirroring the
// GitHub token endpoint's form and credential checks.
func (m *mockProvider) handleToken(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	id, secret, basic := r.BasicAuth()
	if !basic {
		id = r.PostForm.Get("client_id")
		secret = r.PostForm.Get("client_secret")
	}
	if id != mockClientID || secret != mockClientSecret {
		http.Error(w, "bad client credentials", http.StatusUnauthorized)
		return
	}

	code := r.PostForm.Get("code")
	m.mu.Lock()
	user, ok := m.codes[code]
	delete(m.codes, code)
	m.mu.Unlock()
	if !ok {
		http.Error(w, "unknown code", http.StatusBadRequest)
		return
	}

	token := "mock-token-" + user.login
	m.mu.Lock()
	m.tokens[token] = user
	m.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"access_token":%q,"token_type":"bearer","expires_in":3600}`, token)
}

// handleUser returns the identity bound to the presented access token.
func (m *mockProvider) handleUser(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	m.mu.Lock()
	user, ok := m.tokens[token]
	m.mu.Unlock()
	if token == "" || !ok {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"id": %s, "login": %q}`, user.id, user.login)
}

// handleUserLookup answers the username resolution API with a stable
// numeric ID, or 404 for unknown logins.
func (m *mockProvider) handleUserLookup(w http.ResponseWriter, r *http.Request) {
	login := strings.TrimPrefix(r.URL.Path, "/users/")
	user, ok := usersByLogin[login]
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"id": %s, "login": %q}`, user.id, user.login)
}

// forwarded carries the reverse-proxy metadata the forward-auth
// endpoint validates.
type forwarded struct {
	proto string
	host  string
	uri   string
}

func packForwarded() forwarded {
	return forwarded{proto: "https", host: "packapp.apps.surma.technology", uri: "/"}
}

func authAppForwarded() forwarded {
	return forwarded{proto: "https", host: "authapp.apps.surma.technology", uri: "/"}
}

func pubForwarded() forwarded {
	return forwarded{proto: "https", host: "pubapp.apps.surma.technology", uri: "/"}
}

// browser is a minimal cookie-aware HTTP client. The session and
// transaction cookies carry Secure and domain attributes that no real
// cookie jar would attach to loopback requests, so the flow tracks
// cookies manually, like a browser pointed at the auth domain.
type browser struct {
	base    string
	cookies map[string]string
}

func newBrowser(base string) *browser {
	return &browser{base: base, cookies: map[string]string{}}
}

// get performs one GET without following redirects. Absolute targets
// bypass the base address; a non-empty host overrides the Host
// header, standing in for DNS on the auth domain.
func (b *browser) get(t *testing.T, target string, host string, fwd *forwarded) (*http.Response, string) {
	t.Helper()
	requestURL := target
	if !strings.HasPrefix(target, "http://") && !strings.HasPrefix(target, "https://") {
		requestURL = b.base + target
	}
	request, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		t.Fatalf("invalid request URL %q: %v", target, err)
	}
	if host != "" {
		request.Host = host
	}
	if fwd != nil {
		request.Header.Set("X-Forwarded-Proto", fwd.proto)
		request.Header.Set("X-Forwarded-Host", fwd.host)
		request.Header.Set("X-Forwarded-Uri", fwd.uri)
	}
	if header := b.cookieHeader(); header != "" {
		request.Header.Set("Cookie", header)
	}

	client := &http.Client{
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("request to %s failed: %v", target, err)
	}
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("failed to read body for %s: %v", target, err)
	}
	response.Body.Close()
	b.trackCookies(response)
	return response, string(body)
}

func (b *browser) trackCookies(response *http.Response) {
	for _, cookie := range response.Cookies() {
		if cookie.MaxAge < 0 || cookie.Value == "" {
			delete(b.cookies, cookie.Name)
			continue
		}
		b.cookies[cookie.Name] = cookie.Value
	}
}

func (b *browser) cookieHeader() string {
	names := make([]string, 0, len(b.cookies))
	for name := range b.cookies {
		names = append(names, name)
	}
	sort.Strings(names)
	pairs := make([]string, 0, len(names))
	for _, name := range names {
		pairs = append(pairs, name+"="+b.cookies[name])
	}
	return strings.Join(pairs, "; ")
}

// hasSession reports whether the browser holds the session cookie.
func (b *browser) hasSession() bool {
	return b.cookies[sessionCookie] != ""
}

// TestPackagedServer runs the packaged binary end to end.
func TestPackagedServer(t *testing.T) {
	binPath := os.Getenv("SURM_AUTH_BIN")
	if binPath == "" {
		t.Fatalf("SURM_AUTH_BIN is not set; the packaged E2E test must never skip. " +
			"Run it through the flake check (nix build .#checks.x86_64-linux.surm-auth-e2e) " +
			"or point SURM_AUTH_BIN at the wrapped package binary")
	}
	if _, err := os.Stat(binPath); err != nil {
		t.Fatalf("SURM_AUTH_BIN %s not found: %v", binPath, err)
	}

	// State and secrets live outside the source tree.
	root := t.TempDir()
	for name, value := range map[string]string{
		"cookie-secret":        "packaged-test-cookie-secret-0123456789abcdef0123456789",
		"github-client-id":     mockClientID,
		"github-client-secret": mockClientSecret,
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(value), 0600); err != nil {
			t.Fatal(err)
		}
	}

	// The mocked OAuth provider: authorization, token, user, and
	// user lookup all served from the loopback. The granted identity
	// signs in first.
	mock := newMockProvider()
	mock.loginAs(userGrants)
	providerServer := httptest.NewServer(mock)
	t.Cleanup(providerServer.Close)

	policyPath := filepath.Join(root, "policy.json")
	auditPath := filepath.Join(root, "audit.log")
	port := freePort(t)
	configYAML := fmt.Sprintf(`
version: 2
server:
  address: "127.0.0.1:%d"
  base_url: "https://%s"
  auth_domains: ["%s"]
session:
  cookie_name: "%s"
  cookie_domain: ".surma.technology"
  cookie_secret_file: "%s"
  cookie_secure: true
  duration: "1h"
policy:
  file: "%s"
audit:
  file: "%s"
providers:
  github:
    client_id_file: "%s"
    client_secret_file: "%s"
    auth_url: "%s/authorize"
    token_url: "%s/token"
    user_url: "%s/user"
    users_api_url: "%s/users"
bootstrap_admins:
  - provider: "github"
    id: "%s"
apps:
  packapp:
    mode: "allowlist"
    domains: ["packapp.apps.surma.technology"]
    seed_users: ["%s"]
  pubapp:
    mode: "public"
    domains: ["pubapp.apps.surma.technology"]
  intapp:
    mode: "internal"
  authapp:
    mode: "authenticated"
    domains: ["authapp.apps.surma.technology"]
`,
		port, canonicalHost, canonicalHost,
		sessionCookie,
		filepath.Join(root, "cookie-secret"),
		policyPath, auditPath,
		filepath.Join(root, "github-client-id"),
		filepath.Join(root, "github-client-secret"),
		providerServer.URL, providerServer.URL, providerServer.URL, providerServer.URL,
		userAdmin.id,
		userGrants.login,
	)
	configPath := filepath.Join(root, "config.yaml")
	if err := os.WriteFile(configPath, []byte(configYAML), 0600); err != nil {
		t.Fatal(err)
	}

	// Start the actual packaged binary. The environment stays
	// untouched so the nix wrapper pins the packaged templates; the
	// test must never substitute temporary templates.
	cmd := exec.Command(binPath, "-config", configPath)
	cmd.Dir = root
	output := &bytes.Buffer{}
	cmd.Stdout = output
	cmd.Stderr = output
	if err := cmd.Start(); err != nil {
		t.Fatalf("failed to start packaged binary: %v", err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		// cmd.Wait, unlike Process.Wait, also waits for the exec
		// package's output-copy goroutines, so reading the buffer
		// afterwards is race-free.
		_ = cmd.Wait()
		if t.Failed() {
			t.Logf("packaged binary output:\n%s", output.String())
		}
	})

	base := fmt.Sprintf("http://127.0.0.1:%d", port)
	waitForHealth(t, base)

	// The startup seed import resolved "surma" through the mocked
	// user lookup and committed the stable-ID grant.
	persisted := readPersistedPolicy(t, policyPath)
	if !persisted.Imports.SeedApps["packapp"] {
		t.Errorf("seed import marker not persisted: %s", persisted.raw)
	}
	if !hasGrant(persisted, "packapp", "github", userGrants.id) {
		t.Errorf("seed grant for github:%s missing after startup: %s", userGrants.id, persisted.raw)
	}

	// 1. Forward-auth blocks the unauthenticated restricted app and
	// redirects to the login page.
	surma := newBrowser(base)
	packFwd := packForwarded()
	response, body := surma.get(t, "/auth?app=packapp", "", &packFwd)
	if response.StatusCode != http.StatusFound {
		t.Fatalf("forward-auth without session = %d, want 302: %s", response.StatusCode, body)
	}
	if !strings.HasPrefix(response.Header.Get("Location"), fmt.Sprintf("https://%s/login?app=packapp", canonicalHost)) {
		t.Errorf("forward-auth redirect = %q", response.Header.Get("Location"))
	}

	// 2-4. The granted user completes the full browser flow: login
	// page, provider redirect, mocked callback, session issuance.
	callbackResponse, _, authURLPath := driveLogin(t, surma, "packapp", &packFwd)
	if callbackResponse.StatusCode != http.StatusFound {
		t.Fatalf("callback after the granted login = %d, want 302", callbackResponse.StatusCode)
	}
	if location := callbackResponse.Header.Get("Location"); location != "https://packapp.apps.surma.technology/" {
		t.Errorf("callback redirect = %q, want the packapp origin", location)
	}
	if !surma.hasSession() {
		t.Fatalf("no session cookie issued after the granted login (auth URL %q)", authURLPath)
	}

	// 5. The granted user passes forward-auth with identity headers.
	response, body = surma.get(t, "/auth?app=packapp", "", &packFwd)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("forward-auth for the granted user = %d, want 200: %s", response.StatusCode, body)
	}
	if got := response.Header.Get("X-Auth-Request-User"); got != userGrants.login {
		t.Errorf("X-Auth-Request-User = %q, want %q", got, userGrants.login)
	}

	// The callback upserted the user and the policy persisted it.
	persisted = readPersistedPolicy(t, policyPath)
	if _, ok := persisted.Users["github:"+userGrants.id]; !ok {
		t.Errorf("authenticated user github:%s not persisted: %s", userGrants.id, persisted.raw)
	}
	if _, err := os.Stat(policyPath + ".bak"); err != nil {
		t.Error("no backup written for the login commit")
	}

	// 6. A real authenticated user without an app grant is blocked:
	// the callback denies the session for the allowlisted app...
	mock.loginAs(userDenied)
	nobody := newBrowser(base)
	deniedCallback, deniedBody, _ := driveLogin(t, nobody, "packapp", &packFwd)
	if deniedCallback.StatusCode != http.StatusForbidden {
		t.Fatalf("callback without grant = %d, want 403: %s", deniedCallback.StatusCode, deniedBody)
	}
	if !strings.Contains(deniedBody, "Access denied") {
		t.Errorf("denied callback body lacks the block message: %s", deniedBody)
	}
	if nobody.hasSession() {
		t.Error("a session cookie was issued to an ungranted user")
	}

	// ...the same user can authenticate through the authenticated
	// app, which requires no grant...
	authFwd := authAppForwarded()
	authAppCallback, _, _ := driveLogin(t, nobody, "authapp", &authFwd)
	if authAppCallback.StatusCode != http.StatusFound {
		t.Fatalf("callback for the authenticated app = %d, want 302", authAppCallback.StatusCode)
	}
	if !nobody.hasSession() {
		t.Fatal("no session cookie issued for the authenticated app login")
	}
	response, body = nobody.get(t, "/auth?app=packapp", "", &packFwd)
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("forward-auth without grant = %d, want 403: %s", response.StatusCode, body)
	}
	if !strings.Contains(body, "Access denied") {
		t.Errorf("blocked forward-auth body lacks the block message: %s", body)
	}
	response, body = nobody.get(t, "/auth?app=authapp", "", &authFwd)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("forward-auth on the authenticated app = %d, want 200: %s", response.StatusCode, body)
	}

	// ...but still receives a blocking response on the allowlisted
	// app despite holding a valid session.
	response, body = nobody.get(t, "/auth?app=packapp", "", &packFwd)

	// 7. Internal apps are blocked outright, even for sessions.
	anon := newBrowser(base)
	response, body = anon.get(t, "/auth?app=intapp", "", nil)
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("forward-auth for the internal app = %d, want 403: %s", response.StatusCode, body)
	}

	// 8. Unknown apps fail closed with 404.
	response, body = anon.get(t, "/auth?app=unknown", "", nil)
	if response.StatusCode != http.StatusNotFound {
		t.Fatalf("forward-auth for an unknown app = %d, want 404: %s", response.StatusCode, body)
	}

	// 9. Public apps bypass the GitHub gate without a session and
	// without fabricated identity headers.
	pubFwd := pubForwarded()
	response, body = anon.get(t, "/auth?app=pubapp", "", &pubFwd)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("forward-auth for the public app = %d, want 200: %s", response.StatusCode, body)
	}
	if got := response.Header.Get("X-Auth-Request-User"); got != "" {
		t.Errorf("public app fabricated an identity header: %q", got)
	}
}

// driveLogin performs the browser side of one full login for the app:
// it follows the forward-auth redirect, loads the login page, clicks
// through to the mocked provider, and completes the mocked callback.
// It returns the callback response, its body, and the login page's
// provider link for diagnostics.
func driveLogin(t *testing.T, b *browser, app string, fwd *forwarded) (*http.Response, string, string) {
	t.Helper()

	// Forward-auth hands the browser to the login page.
	response, body := b.get(t, "/auth?app="+app, "", fwd)
	if response.StatusCode != http.StatusFound {
		t.Fatalf("forward-auth did not redirect to login: %d %s", response.StatusCode, body)
	}
	loginURL := rewriteToLoopback(t, response.Header.Get("Location"))

	// The login page renders through the packaged templates.
	response, body = b.get(t, loginURL, canonicalHost, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("login page = %d, want 200: %s", response.StatusCode, body)
	}
	if !strings.Contains(body, "Authentication Required") {
		t.Errorf("login page lacks the packaged template copy: %s", body)
	}
	if !strings.Contains(body, app) {
		t.Errorf("login page lacks the app name %q: %s", app, body)
	}

	// Clicking "Login with GitHub" starts the OAuth transaction.
	authURLPath := extractAuthURL(t, body)
	response, body = b.get(t, authURLPath, canonicalHost, nil)
	if response.StatusCode != http.StatusFound {
		t.Fatalf("login did not redirect to the provider: %d %s", response.StatusCode, body)
	}
	providerURL := response.Header.Get("Location")
	if !strings.HasPrefix(providerURL, "http://") || !strings.Contains(providerURL, "/authorize") {
		t.Fatalf("provider redirect does not target the mocked authorize endpoint: %q", providerURL)
	}

	// The provider consents and redirects back with a code.
	response, body = b.get(t, providerURL, "", nil)
	if response.StatusCode != http.StatusFound {
		t.Fatalf("mocked authorize did not redirect back: %d %s", response.StatusCode, body)
	}
	callbackPath := rewriteToLoopback(t, response.Header.Get("Location"))
	if !strings.Contains(callbackPath, "code=") {
		t.Fatalf("mocked callback redirect carries no code: %q", callbackPath)
	}

	// The real binary exchanges the code and issues the session.
	callbackResponse, callbackBody := b.get(t, callbackPath, canonicalHost, nil)
	return callbackResponse, callbackBody, authURLPath
}

// rewriteToLoopback replaces the canonical auth origin with the local
// server address, standing in for DNS that points the auth domain at
// the test server.
func rewriteToLoopback(t *testing.T, location string) string {
	t.Helper()
	rewritten := strings.Replace(location, "https://"+canonicalHost, "", 1)
	if rewritten == location {
		t.Fatalf("redirect does not target the canonical auth host: %q", location)
	}
	return rewritten
}

// extractAuthURL pulls the provider link out of the rendered login
// page, undoing the HTML attribute escaping.
func extractAuthURL(t *testing.T, body string) string {
	t.Helper()
	re := regexp.MustCompile(`<a href="(/login/github\?[^"]+)"`)
	match := re.FindStringSubmatch(body)
	if match == nil {
		t.Fatalf("login page lacks the provider link: %s", body)
	}
	return strings.ReplaceAll(match[1], "&amp;", "&")
}

// persistedPolicy is the on-disk policy document the binary commits.
type persistedPolicy struct {
	Users map[string]struct {
		Role string `json:"role"`
	} `json:"users"`
	Grants map[string][]struct {
		Provider string `json:"provider"`
		ID       string `json:"id"`
	} `json:"grants"`
	Imports struct {
		SeedApps map[string]bool `json:"seed_apps"`
	} `json:"imports"`
	raw string
}

func readPersistedPolicy(t *testing.T, path string) persistedPolicy {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read persisted policy: %v", err)
	}
	var policy persistedPolicy
	if err := json.Unmarshal(data, &policy); err != nil {
		t.Fatalf("persisted policy invalid: %v", err)
	}
	policy.raw = string(data)
	return policy
}

func hasGrant(policy persistedPolicy, app, provider, id string) bool {
	for _, grant := range policy.Grants[app] {
		if grant.Provider == provider && grant.ID == id {
			return true
		}
	}
	return false
}

// --- helpers ---

func freePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func waitForHealth(t *testing.T, base string) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		response, err := http.Get(base + "/health")
		if err == nil {
			response.Body.Close()
			if response.StatusCode == 200 {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("packaged server never became healthy")
}
