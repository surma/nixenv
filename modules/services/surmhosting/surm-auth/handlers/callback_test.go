package handlers

import (
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/surma/surm-auth/auth"
)

// beginLogin drives GET /login/github and returns the signed state and
// the transaction cookie.
func beginLogin(t *testing.T, server *Server, target string) (string, *http.Cookie) {
	t.Helper()
	recorder := get(server, sessionRequest(http.MethodGet, target, nil))
	if recorder.Code != 302 {
		t.Fatalf("initiation status = %d, want 302; body: %s", recorder.Code, recorder.Body.String())
	}
	state := parseStateParam(t, recorder.Header().Get("Location"))
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != txCookie {
		t.Fatalf("no transaction cookie set: %v", cookies)
	}
	return state, cookies[0]
}

// callbackRequest builds the callback request with state, code, and
// the transaction cookie.
func callbackRequest(t *testing.T, server *Server, state string, txCookie *http.Cookie, code string, extraQuery url.Values) *http.Request {
	t.Helper()
	target := "/callback?code=" + url.QueryEscape(code) + "&state=" + url.QueryEscape(state)
	for key, values := range extraQuery {
		for _, v := range values {
			target += "&" + key + "=" + url.QueryEscape(v)
		}
	}
	r := sessionRequest(http.MethodGet, target, txCookie)
	return r
}

func TestCallbackFullFlowWithAppGrant(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	// Seed a grant for the login user.
	if err := server.deps.Policy.AddGrant("testapp", "github", "2000", "surma", "admin"); err != nil {
		t.Fatal(err)
	}

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=https%3A%2F%2Ftestapp.apps.surma.technology%2Fback")
	recorder := get(server, callbackRequest(t, server, state, tx, "good-code", nil))

	if recorder.Code != 302 {
		t.Fatalf("callback status = %d, body: %s", recorder.Code, recorder.Body.String())
	}
	if got := recorder.Header().Get("Location"); got != "https://testapp.apps.surma.technology/back" {
		t.Errorf("redirect = %q", got)
	}

	// A v2 session cookie was set.
	var sessionCookie *http.Cookie
	for _, c := range recorder.Result().Cookies() {
		if c.Name == "_surm_auth2" {
			sessionCookie = c
		}
	}
	if sessionCookie == nil {
		t.Fatalf("session cookie missing: %v", recorder.Result().Cookies())
	}

	// Display data was upserted without touching the role.
	user := server.deps.Policy.Snapshot().Users["github:2000"]
	if user == nil || user.Username != "surma" {
		t.Fatalf("login user not upserted: %+v", user)
	}

	// A login success was audited.
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "login_success" || last.App != "testapp" || last.Subject != "github:2000" {
		t.Errorf("last audit event = %+v", last)
	}

	// The transaction cookie is consumed and cleared.
	clearCookie := recorder.Result().Cookies()
	if len(clearCookie) == 1 && clearCookie[0].MaxAge != -1 {
		// Session cookie only; the cleared tx cookie is a second
		// Set-Cookie header.
	}
	var txCleared bool
	for _, c := range recorder.Header().Values("Set-Cookie") {
		if strings.HasPrefix(c, txCookie+"=") && strings.Contains(c, "Max-Age=0") {
			txCleared = true
		}
	}
	if !txCleared {
		t.Error("transaction cookie was not cleared after the callback")
	}
}

func TestCallbackWithoutGrantDenied(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=https%3A%2F%2Ftestapp.apps.surma.technology%2Fback")
	recorder := get(server, callbackRequest(t, server, state, tx, "good-code", nil))

	if recorder.Code != 403 {
		t.Fatalf("callback without grant: status = %d, want 403", recorder.Code)
	}
	for _, c := range recorder.Result().Cookies() {
		if c.Name == "_surm_auth2" {
			t.Error("a session was issued despite the denial")
		}
	}
	events, _ := server.deps.Audit.Latest(200)
	last := events[len(events)-1]
	if last.Event != "login_denied" || last.App != "testapp" {
		t.Errorf("last audit event = %+v", last)
	}
}

func TestCallbackAuthHostLogin(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	// An anonymous /admin visit redirects to login with redirect=/admin.
	adminRedirect := get(server, sessionRequest(http.MethodGet, "/admin", nil))
	if adminRedirect.Code != 302 {
		t.Fatalf("anonymous /admin status = %d, want 302", adminRedirect.Code)
	}

	// Auth-host login without an app completes and returns to /admin.
	state, tx := beginLogin(t, server, "/login/github?redirect=%2Fadmin")
	recorder := get(server, callbackRequest(t, server, state, tx, "good-code", nil))
	if recorder.Code != 302 {
		t.Fatalf("auth-host callback status = %d, want 302", recorder.Code)
	}
	if got := recorder.Header().Get("Location"); got != "/admin" {
		t.Errorf("auth-host redirect = %q, want /admin", got)
	}
	// The session cookie is set and the transaction cookie is cleared.
	var sessionCookie *http.Cookie
	var txCleared bool
	for _, c := range recorder.Result().Cookies() {
		if c.Name == "_surm_auth2" {
			sessionCookie = c
		}
	}
	for _, raw := range recorder.Header().Values("Set-Cookie") {
		if strings.HasPrefix(raw, txCookie+"=") && strings.Contains(raw, "Max-Age=0") {
			txCleared = true
		}
	}
	if sessionCookie == nil {
		t.Fatal("no session cookie on auth-host login")
	}
	if !txCleared {
		t.Error("transaction cookie not cleared on auth-host login")
	}

	// The identity is verified but holds no admin role: /admin must
	// answer 403.
	denied := get(server, sessionRequest(http.MethodGet, "/admin", sessionCookie))
	if denied.Code != 403 {
		t.Errorf("non-admin /admin status = %d, want 403", denied.Code)
	}
}

func TestCallbackPublicAppIssuesSession(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	state, tx := beginLogin(t, server, "/login/github?app=pubapp&redirect=https%3A%2F%2Fpubapp.apps.surma.technology%2F")
	recorder := get(server, callbackRequest(t, server, state, tx, "good-code", nil))
	if recorder.Code != 302 {
		t.Fatalf("public-app callback status = %d, want 302", recorder.Code)
	}
}

func TestCallbackReplayRejected(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=%2F")
	if err := server.deps.Policy.AddGrant("testapp", "github", "2000", "surma", "admin"); err != nil {
		t.Fatal(err)
	}

	first := get(server, callbackRequest(t, server, state, tx, "good-code", nil))
	if first.Code != 302 {
		t.Fatalf("first callback status = %d", first.Code)
	}

	// Replaying the same state and cookie must fail even with a fresh
	// transaction cookie value.
	replay := get(server, callbackRequest(t, server, state, tx, "good-code", nil))
	if replay.Code != 400 {
		t.Fatalf("replayed callback status = %d, want 400", replay.Code)
	}
}

func TestCallbackRequiresTransactionCookie(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	state, _ := beginLogin(t, server, "/login/github?app=testapp&redirect=%2F")
	// No transaction cookie at all.
	r := sessionRequest(http.MethodGet, "/callback?code=good-code&state="+url.QueryEscape(state), nil)
	recorder := get(server, r)
	if recorder.Code != 400 {
		t.Errorf("cookie-less callback status = %d, want 400", recorder.Code)
	}

	// A cookie from a different browser does not match the nonce.
	foreign := &http.Cookie{Name: txCookie, Value: "forged-nonce"}
	recorder = get(server, callbackRequest(t, server, state, foreign, "good-code", nil))
	if recorder.Code != 400 {
		t.Errorf("forged cookie callback status = %d, want 400", recorder.Code)
	}
}

func TestCallbackExpiredTransaction(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	// Craft a signed state whose Unix-second expiry already passed.
	data := auth.StateData{
		Provider:  "github",
		Redirect:  "/",
		Nonce:     "expired-nonce",
		IssuedAt:  time.Now().Add(-time.Hour).Unix(),
		ExpiresAt: time.Now().Add(-time.Minute).Unix(),
	}
	state, err := auth.EncodeState(data, []byte(cookieSecret))
	if err != nil {
		t.Fatal(err)
	}

	recorder := get(server, callbackRequest(t, server, state,
		&http.Cookie{Name: txCookie, Value: data.Nonce}, "good-code", nil))
	if recorder.Code != 400 {
		t.Errorf("expired transaction status = %d, want 400", recorder.Code)
	}
}

func TestCallbackTamperedState(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=%2F")
	// Corrupt the state payload.
	mutated := state[:len(state)-4] + "AAAA"
	recorder := get(server, callbackRequest(t, server, mutated, tx, "good-code", nil))
	if recorder.Code != 400 {
		t.Errorf("tampered state status = %d, want 400", recorder.Code)
	}
}

func TestCallbackMissingParameters(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet, "/callback", nil))
	if recorder.Code != 400 {
		t.Errorf("parameter-less callback status = %d, want 400", recorder.Code)
	}
}

func TestCallbackOAuthErrorParameter(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, sessionRequest(http.MethodGet,
		"/callback?error=access_denied&error_description=User+denied", nil))
	if recorder.Code != 403 {
		t.Errorf("OAuth error callback status = %d, want 403", recorder.Code)
	}
}

func TestCallbackExchangeFailure(t *testing.T) {
	provider := newFakeProvider()
	server := newTestServer(t, testConfig(t), provider, 0)

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=%2F")
	recorder := get(server, callbackRequest(t, server, state, tx, "bad-code", nil))
	if recorder.Code != 500 {
		t.Errorf("exchange failure status = %d, want 500", recorder.Code)
	}
}

func TestCallbackUnknownStateProvider(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	data := auth.StateData{
		Provider:  "gitlab",
		Redirect:  "/",
		Nonce:     "n",
		IssuedAt:  time.Now().Unix(),
		ExpiresAt: time.Now().Add(time.Minute).Unix(),
	}
	state, err := auth.EncodeState(data, []byte(cookieSecret))
	if err != nil {
		t.Fatal(err)
	}
	recorder := get(server, callbackRequest(t, server, state, &http.Cookie{Name: txCookie, Value: "n"}, "good-code", nil))
	if recorder.Code != 400 {
		t.Errorf("unknown provider status = %d, want 400", recorder.Code)
	}
}

func TestCallbackPolicyUnavailable(t *testing.T) {
	cfg := testConfig(t)
	server := newTestServer(t, cfg, newFakeProvider(), 0)

	state, tx := beginLogin(t, server, "/login/github?app=testapp&redirect=%2F")
	if err := writeCorruptPolicy(t, cfg.Policy.File); err != nil {
		t.Fatal(err)
	}
	if err := server.deps.Policy.Reload(); err == nil {
		t.Fatal("corrupt reload succeeded")
	}

	recorder := get(server, callbackRequest(t, server, state, tx, "good-code", nil))
	if recorder.Code != 503 {
		t.Errorf("callback with unavailable policy status = %d, want 503", recorder.Code)
	}
}
