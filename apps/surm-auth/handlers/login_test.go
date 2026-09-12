package handlers

import (
	"html"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestLoginPageWithoutApp(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/login", nil))
	if recorder.Code != 200 {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.HasPrefix(body, "LOGIN") {
		t.Errorf("login page did not render: %q", body)
	}
	if strings.Contains(body, "|") && extractQueryParam(body, "app") != "" {
		t.Errorf("app-less login carries an app parameter: %q", body)
	}
}

func TestLoginPageWithApp(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/login?app=testapp&redirect=https://testapp.apps.surma.technology/x", nil))
	if recorder.Code != 200 {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if !strings.Contains(recorder.Body.String(), "|testapp|") {
		t.Errorf("app name missing from login page: %q", recorder.Body.String())
	}
}

func TestLoginPageRejectsUnknownAndInternalApps(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/login?app=ghost", nil))
	if recorder.Code != 404 {
		t.Errorf("unknown app: status = %d, want 404", recorder.Code)
	}
	recorder = get(server, sessionRequest(http.MethodGet, "/login?app=intapp", nil))
	if recorder.Code != 404 {
		t.Errorf("internal app: status = %d, want 404", recorder.Code)
	}
}

func TestLoginPageInvalidRedirectFallsBack(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	for _, bad := range []string{
		"https://evil.example.com/steal",
		"//evil.example.com",
		"http://testapp.apps.surma.technology/",
		"https://user@evil.example.com/",
	} {
		recorder := get(server, sessionRequest(http.MethodGet, "/login?app=testapp&redirect="+url.QueryEscape(bad), nil))
		if recorder.Code != 200 {
			t.Fatalf("redirect %q: status = %d, want 200", bad, recorder.Code)
		}
		authURL := extractAuthURL(recorder.Body.String())
		if authURL == "" {
			t.Fatalf("no AuthURL rendered: %q", recorder.Body.String())
		}
		parsed, err := url.Parse(authURL)
		if err != nil {
			t.Fatalf("bad AuthURL %q: %v", authURL, err)
		}
		if got := parsed.Query().Get("redirect"); got != "/" {
			t.Errorf("redirect %q fell back to %q, want /", bad, got)
		}
	}
}

func TestLoginGitHubInitiatesTransaction(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet,
		"/login/github?app=testapp&redirect=https%3A%2F%2Ftestapp.apps.surma.technology%2Fback", nil))
	if recorder.Code != 302 {
		t.Fatalf("status = %d, want 302 to provider", recorder.Code)
	}

	// The redirect goes to the provider with a signed state.
	location := recorder.Header().Get("Location")
	if !strings.HasPrefix(location, "https://github.test/oauth?state=") {
		t.Fatalf("provider redirect = %q", location)
	}

	// A host-only transaction cookie binds the browser to the
	// transaction.
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("expected one transaction cookie, got %d", len(cookies))
	}
	tx := cookies[0]
	if tx.Name != txCookie {
		t.Errorf("transaction cookie name = %q", tx.Name)
	}
	if tx.Domain != "" {
		t.Errorf("transaction cookie must be host-only, has Domain=%q", tx.Domain)
	}
	if !tx.HttpOnly || !tx.Secure {
		t.Error("transaction cookie must be Secure and HttpOnly")
	}
	raw := recorder.Header().Get("Set-Cookie")
	if !strings.Contains(raw, "SameSite=Lax") {
		t.Errorf("Set-Cookie = %q", raw)
	}

	// The outstanding transaction must be consumable exactly once.
	state := parseStateParam(t, location)
	decoded, err := decodeStateForTest(state)
	if err != nil {
		t.Fatalf("state undecodable: %v", err)
	}
	if decoded.Nonce != tx.Value {
		t.Errorf("transaction cookie value does not bind to the state nonce")
	}
	if decoded.App != "testapp" {
		t.Errorf("state app = %q", decoded.App)
	}
	if decoded.Redirect != "https://testapp.apps.surma.technology/back" {
		t.Errorf("state redirect = %q", decoded.Redirect)
	}
	if _, err := server.deps.Tx.Consume(decoded.Nonce); err != nil {
		t.Errorf("transaction not outstanding: %v", err)
	}
}

func TestLoginGitHubCanonicalizesAlias(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	r := httptest.NewRequest(http.MethodGet, "https://auth.apps.surma.technology/login/github?app=testapp", nil)
	r.Host = "auth.apps.surma.technology"
	recorder := get(server, r)
	if recorder.Code != 302 {
		t.Fatalf("alias initiation: status = %d, want 302", recorder.Code)
	}
	if got := recorder.Header().Get("Location"); !strings.HasPrefix(got, canonicalBase+"/login/github") {
		t.Errorf("alias redirect = %q", got)
	}
	// The redirect response must not already begin the transaction.
	if len(recorder.Result().Cookies()) != 0 {
		t.Error("alias request started a transaction before canonicalization")
	}
}

func TestLoginGitHubRejectsUnknownApp(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/login/github?app=ghost", nil))
	if recorder.Code != 404 {
		t.Errorf("unknown app initiation: status = %d, want 404", recorder.Code)
	}
	recorder = get(server, sessionRequest(http.MethodGet, "/login/github?app=intapp", nil))
	if recorder.Code != 404 {
		t.Errorf("internal app initiation: status = %d, want 404", recorder.Code)
	}
}

func TestLandingPage(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/", nil))
	if recorder.Code != 200 {
		t.Fatalf("landing status = %d, want 200", recorder.Code)
	}
	if strings.Contains(recorder.Body.String(), "LOGGEDIN") {
		t.Errorf("anonymous landing claims a session: %q", recorder.Body.String())
	}

	admin := adminUser()
	recorder = get(server, sessionRequest(http.MethodGet, "/", mintCookie(t, server, admin)))
	if recorder.Code != 200 {
		t.Fatalf("landing (logged in) status = %d, want 200", recorder.Code)
	}
	if !strings.Contains(recorder.Body.String(), "LOGGEDIN|boss|ADMIN") {
		t.Errorf("admin landing lacks the username or admin control: %q", recorder.Body.String())
	}

	nonAdmin := plainUser("2001")
	recorder = get(server, sessionRequest(http.MethodGet, "/", mintCookie(t, server, nonAdmin)))
	if recorder.Code != 200 {
		t.Fatalf("non-admin landing status = %d, want 200", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, "LOGGEDIN|user2001") {
		t.Errorf("non-admin landing lacks the username: %q", body)
	}
	if strings.Contains(body, "|ADMIN") {
		t.Errorf("non-admin landing shows the admin control: %q", body)
	}
}

// --- helpers ---

func extractAuthURL(body string) string {
	for _, part := range strings.Split(body, "|") {
		if strings.HasPrefix(part, "/login/github") {
			// html/template escapes ampersands in text context.
			return html.UnescapeString(part)
		}
	}
	return ""
}

func extractQueryParam(body, key string) string {
	authURL := extractAuthURL(body)
	if authURL == "" {
		return ""
	}
	parsed, err := url.Parse(authURL)
	if err != nil {
		return ""
	}
	return parsed.Query().Get(key)
}

func parseStateParam(t *testing.T, location string) string {
	t.Helper()
	parsed, err := url.Parse(location)
	if err != nil {
		t.Fatal(err)
	}
	state := parsed.Query().Get("state")
	if state == "" {
		t.Fatalf("no state in %q", location)
	}
	return state
}
