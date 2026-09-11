package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/surma/surm-auth/auth"
)

// TestPackagedServer starts the packaged binary with a valid temporary
// config and synthetic secrets and verifies health, login rendering,
// admin rendering, and a persisted grant mutation.
func TestPackagedServer(t *testing.T) {
	binPath := os.Getenv("SURM_AUTH_BIN")
	if binPath == "" {
		t.Skip("SURM_AUTH_BIN not set; build the package and point SURM_AUTH_BIN at its binary")
	}
	if _, err := os.Stat(binPath); err != nil {
		t.Fatalf("SURM_AUTH_BIN %s not found: %v", binPath, err)
	}

	root := t.TempDir() // Outside the source tree.
	templates := filepath.Join(root, "templates")
	if err := os.MkdirAll(templates, 0700); err != nil {
		t.Fatal(err)
	}
	writeFixtureTemplates(t, templates)

	// Synthetic secrets.
	cookieSecret := "packaged-test-cookie-secret-0123456789abcdef0123456789"
	secrets := map[string]string{
		"cookie-secret":        cookieSecret,
		"github-client-id":     "synthetic-client-id",
		"github-client-secret": "synthetic-client-secret",
	}
	for name, value := range secrets {
		if err := os.WriteFile(filepath.Join(root, name), []byte(value), 0600); err != nil {
			t.Fatal(err)
		}
	}

	// Pre-seed a policy with one grant to mutate. No seed users are
	// declared, so startup never resolves usernames (no network).
	policyPath := filepath.Join(root, "policy.json")
	auditPath := filepath.Join(root, "audit.log")
	preSeed := `{
  "version": 1,
  "users": {
    "github:1000": {"provider": "github", "id": "1000", "username": "boss", "role": "admin", "first_seen": "2026-01-01T00:00:00Z", "last_seen": "2026-01-01T00:00:00Z"},
    "github:999": {"provider": "github", "id": "999", "username": "stale", "role": "user", "first_seen": "2026-01-01T00:00:00Z", "last_seen": "2026-01-01T00:00:00Z"}
  },
  "grants": {"packapp": [{"provider": "github", "id": "999", "username": "stale"}]},
  "imports": {"seed_apps": {"packapp": true}},
  "updated_at": "2026-01-01T00:00:00Z",
  "updated_by": "test"
}`
	if err := os.WriteFile(policyPath, []byte(preSeed), 0600); err != nil {
		t.Fatal(err)
	}

	port := freePort(t)
	configYAML := fmt.Sprintf(`
version: 2
server:
  address: "127.0.0.1:%d"
  base_url: "https://auth.surma.technology"
  auth_domains: ["auth.surma.technology"]
session:
  cookie_name: "_surm_auth2"
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
bootstrap_admins:
  - provider: "github"
    id: "1000"
apps:
  packapp:
    mode: "allowlist"
    domains: ["packapp.apps.surma.technology"]
`, port,
		filepath.Join(root, "cookie-secret"),
		policyPath, auditPath,
		filepath.Join(root, "github-client-id"),
		filepath.Join(root, "github-client-secret"))
	configPath := filepath.Join(root, "config.yaml")
	if err := os.WriteFile(configPath, []byte(configYAML), 0600); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(binPath, "-config", configPath)
	cmd.Dir = root // Run outside the source tree.
	// The nix wrapper pins SURM_AUTH_TEMPLATES itself; for locally
	// built binaries the test provides a temporary template path.
	cmd.Env = append(os.Environ(), "SURM_AUTH_TEMPLATES="+templates)
	output := &bytes.Buffer{}
	cmd.Stdout = output
	cmd.Stderr = output
	if err := cmd.Start(); err != nil {
		t.Fatalf("failed to start packaged binary: %v", err)
	}
	defer func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}()

	base := fmt.Sprintf("http://127.0.0.1:%d", port)
	waitForHealth(t, base)

	// Health reports readiness.
	response, err := http.Get(base + "/health")
	if err != nil {
		t.Fatalf("health request failed: %v", err)
	}
	body, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != 200 || !strings.Contains(string(body), "OK") {
		t.Fatalf("health = %d %q", response.StatusCode, body)
	}

	// Login rendering with a temporary template path. Browser-facing
	// routes must arrive on the canonical auth host.
	response, err = getWithCookie(base+"/login?app=packapp", nil, "auth.surma.technology")
	if err != nil {
		t.Fatalf("login request failed: %v", err)
	}
	loginBody, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != 200 || !strings.Contains(string(loginBody), "packapp") {
		t.Fatalf("login = %d %q", response.StatusCode, loginBody)
	}

	// A test-signed admin session cookie.
	adminCookie := mintAdminCookie(t, cookieSecret)

	response, err = getWithCookie(base+"/admin", adminCookie, "auth.surma.technology")
	if err != nil {
		t.Fatal(err)
	}
	adminBody, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatalf("admin = %d %q", response.StatusCode, adminBody)
	}
	if !strings.Contains(string(adminBody), "packapp") || !strings.Contains(string(adminBody), "github:1000") {
		t.Errorf("admin page lacks expected content: %s", adminBody)
	}

	// A persisted grant mutation through the admin UI.
	response, err = getWithCookie(base+"/admin/apps/packapp", adminCookie, "auth.surma.technology")
	if err != nil {
		t.Fatal(err)
	}
	appBody, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatalf("app page = %d", response.StatusCode)
	}
	csrf := extractDeleteCSRF(t, string(appBody))

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("app", "packapp")
	form.Set("provider", "github")
	form.Set("id", "999")
	mutation, err := http.NewRequest(http.MethodPost, base+"/admin/grants/delete", strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatal(err)
	}
	mutation.Header.Set("Origin", "https://auth.surma.technology")
	mutation.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	mutation.Host = "auth.surma.technology"
	mutation.AddCookie(adminCookie)

	client := &http.Client{
		CheckRedirect: func(req *http.Request, via []*http.Request) error { return http.ErrUseLastResponse },
	}
	response, err = client.Do(mutation)
	if err != nil {
		t.Fatalf("grant mutation failed: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != 303 {
		t.Fatalf("grant mutation status = %d, want 303", response.StatusCode)
	}

	// The persisted policy no longer holds the grant.
	data, err := os.ReadFile(policyPath)
	if err != nil {
		t.Fatal(err)
	}
	var persisted struct {
		Grants map[string][]struct {
			Provider string `json:"provider"`
			ID       string `json:"id"`
		} `json:"grants"`
	}
	if err := json.Unmarshal(data, &persisted); err != nil {
		t.Fatalf("persisted policy invalid: %v", err)
	}
	if len(persisted.Grants["packapp"]) != 0 {
		t.Errorf("grant still persisted after mutation: %s", data)
	}
	if _, err := os.Stat(policyPath + ".bak"); err != nil {
		t.Error("no backup written for the mutation")
	}
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
	deadline := time.Now().Add(15 * time.Second)
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

func mintAdminCookie(t *testing.T, secret string) *http.Cookie {
	t.Helper()
	now := time.Now()
	claims := &auth.Claims{
		Provider: "github",
		UID:      "1000",
		Username: "boss",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "github:1000",
			Issuer:    "surm-auth",
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
			ID:        "packaged-test-jti",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return &http.Cookie{Name: "_surm_auth2", Value: signed}
}

func getWithCookie(url string, cookie *http.Cookie, host string) (*http.Response, error) {
	request, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if host != "" {
		request.Host = host
	}
	if cookie != nil {
		request.AddCookie(cookie)
	}
	return http.DefaultClient.Do(request)
}

// extractDeleteCSRF pulls the CSRF token out of the grant-delete form.
func extractDeleteCSRF(t *testing.T, body string) string {
	t.Helper()
	re := regexp.MustCompile(`action="/admin/grants/delete"[\s\S]*?name="csrf_token" value="([^"]+)"`)
	match := re.FindStringSubmatch(body)
	if match == nil {
		t.Fatalf("no grant-delete form in the app page: %s", body)
	}
	return match[1]
}

// writeFixtureTemplates writes a minimal template set. When the real
// nix wrapper runs, its packaged templates override this directory.
func writeFixtureTemplates(t *testing.T, dir string) {
	t.Helper()
	files := map[string]string{
		"login.html": `<!DOCTYPE html><html><body>
<h1>Authentication Required</h1><p>{{if .App}}access {{.App}}{{end}}</p>
<a href="{{.AuthURL}}">Login with GitHub</a></body></html>`,
		"error.html": `<!DOCTYPE html><html><body><p>{{.Error}}</p></body></html>`,
		"admin.html": `<!DOCTYPE html><html><body>
{{range .Apps}}<span>{{.Key}}:{{.Mode}}:{{.Grants}}</span>{{end}}
{{range .Users}}<span>{{.Subject}}:{{.Role}}{{if .Managed}} managed by Nix{{end}}</span>{{end}}</body></html>`,
		"admin_app.html": `<!DOCTYPE html><html><body>
{{range .Grants}}<form method="POST" action="/admin/grants/delete">
<input type="hidden" name="csrf_token" value="{{$.CSRFDelete}}">
<input type="hidden" name="app" value="{{$.App.Key}}">
</form>{{end}}
<form method="POST" action="/admin/apps/{{.App.Key}}/grants">
<input type="hidden" name="csrf_token" value="{{.CSRFGrant}}">
</form></body></html>`,
		"audit.html": `<!DOCTYPE html><html><body>{{range .Events}}<span>{{.Event}}</span>{{end}}</body></html>`,
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
