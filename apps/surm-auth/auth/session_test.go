package auth

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

var testUser = &User{
	Provider: "github",
	ID:       "987654",
	Username: "surma",
	Email:    "surma@example.com",
	Avatar:   "https://avatars.example/surma.png",
}

func newTestManager() *Manager {
	return NewManager([]byte("test-secret-0123456789abcdef0123456789abcdef"), "_surm_auth2", ".surma.technology", true, time.Hour)
}

func requestWithCookie(cookie *http.Cookie) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "https://auth.surma.technology/", nil)
	r.AddCookie(cookie)
	return r
}

func TestSessionCreateValidateRoundtrip(t *testing.T) {
	manager := newTestManager()

	recorder := httptest.NewRecorder()
	if err := manager.Create(recorder, testUser); err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("expected one cookie, got %d", len(cookies))
	}

	claims, err := manager.Validate(requestWithCookie(cookies[0]))
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}
	if claims.Provider != "github" || claims.UID != "987654" {
		t.Errorf("identity = %s/%s", claims.Provider, claims.UID)
	}
	if claims.Subject != "github:987654" {
		t.Errorf("subject = %q", claims.Subject)
	}
	if claims.Username != "surma" || claims.Email != "surma@example.com" {
		t.Errorf("display data = %q/%q", claims.Username, claims.Email)
	}
	if claims.Issuer != "surm-auth" {
		t.Errorf("issuer = %q", claims.Issuer)
	}
	if claims.ExpiresAt == nil || !claims.ExpiresAt.After(time.Now()) {
		t.Error("token lacks a future expiration")
	}
	if claims.ID == "" {
		t.Error("token lacks a jti session ID")
	}
}

func TestSessionCookieAttributes(t *testing.T) {
	manager := newTestManager()
	recorder := httptest.NewRecorder()
	if err := manager.Create(recorder, testUser); err != nil {
		t.Fatal(err)
	}

	cookie := recorder.Result().Cookies()[0]
	if cookie.Name != "_surm_auth2" {
		t.Errorf("cookie name = %q", cookie.Name)
	}
	// Assert the raw wire format; Go's cookie parser strips the
	// leading dot from Domain when reading it back.
	raw := recorder.Header().Get("Set-Cookie")
	for _, want := range []string{"Domain=surma.technology", "Path=/", "HttpOnly", "Secure", "SameSite=Lax"} {
		if !strings.Contains(raw, want) {
			t.Errorf("Set-Cookie %q lacks %q", raw, want)
		}
	}
	if cookie.Domain != "surma.technology" {
		t.Errorf("cookie domain = %q", cookie.Domain)
	}
}

func TestSessionValidateRejectsWrongAlgorithm(t *testing.T) {
	manager := newTestManager()

	// Sign the same claims with HS512; the manager must reject
	// anything that is not HS256.
	claims := &Claims{
		Provider:         "github",
		UID:              "1",
		RegisteredClaims: freshRegisteredClaims(time.Hour),
	}
	token := jwtNewWithClaimsHS512(claims, []byte("test-secret-0123456789abcdef0123456789abcdef"))

	request := requestWithCookie(&http.Cookie{Name: "_surm_auth2", Value: token})
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("HS512 token accepted")
	}
}

func TestSessionValidateRejectsWrongIssuer(t *testing.T) {
	manager := newTestManager()

	recorder := httptest.NewRecorder()
	if err := manager.Create(recorder, testUser); err != nil {
		t.Fatal(err)
	}
	cookie := recorder.Result().Cookies()[0]

	// A token from a different issuer must fail.
	forged := jwtSignClaims(t, &Claims{
		Provider:         "github",
		UID:              "987654",
		RegisteredClaims: registeredClaims(issuerOther, time.Hour),
	}, manager.secret)
	request := requestWithCookie(&http.Cookie{Name: "_surm_auth2", Value: forged})
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("token with wrong issuer accepted")
	}
	_ = cookie
}

func TestSessionValidateRejectsExpired(t *testing.T) {
	secret := []byte("test-secret-0123456789abcdef0123456789abcdef")
	manager := NewManager(secret, "_surm_auth2", ".surma.technology", true, -time.Minute)

	recorder := httptest.NewRecorder()
	if err := manager.Create(recorder, testUser); err != nil {
		t.Fatal(err)
	}
	request := requestWithCookie(recorder.Result().Cookies()[0])
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("expired token accepted")
	}
}

func TestSessionValidateRejectsUsernameOnlyShape(t *testing.T) {
	// The v1 shape had sub=<username> and no provider/uid claims.
	manager := newTestManager()
	forged := jwtSignClaims(t, &Claims{
		Username:         "surma",
		RegisteredClaims: registeredClaims(sessionIssuer, time.Hour),
	}, manager.secret)

	request := requestWithCookie(&http.Cookie{Name: "_surm_auth2", Value: forged})
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("username-only v1 token accepted")
	}
}

func TestSessionValidateRejectsSubjectMismatch(t *testing.T) {
	manager := newTestManager()
	forged := jwtSignClaims(t, &Claims{
		Provider:         "github",
		UID:              "1",
		RegisteredClaims: registeredClaimsWithSubject(sessionIssuer, "surma", time.Hour),
	}, manager.secret)

	request := requestWithCookie(&http.Cookie{Name: "_surm_auth2", Value: forged})
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("token whose subject does not match its identity accepted")
	}
}

func TestSessionValidateRejectsGarbageAndMissing(t *testing.T) {
	manager := newTestManager()

	request := httptest.NewRequest(http.MethodGet, "https://x/", nil)
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("request without cookie accepted")
	}

	request = requestWithCookie(&http.Cookie{Name: "_surm_auth2", Value: "garbage"})
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("garbage token accepted")
	}

	// A token signed with a different secret must fail.
	other := NewManager([]byte("another-secret-0123456789abcdef01234567"), "_surm_auth2", ".surma.technology", true, time.Hour)
	recorder := httptest.NewRecorder()
	if err := other.Create(recorder, testUser); err != nil {
		t.Fatal(err)
	}
	request = requestWithCookie(recorder.Result().Cookies()[0])
	if _, err := manager.Validate(request); err == nil {
		t.Fatal("token signed with foreign secret accepted")
	}
}

func TestSessionClear(t *testing.T) {
	manager := newTestManager()
	recorder := httptest.NewRecorder()
	manager.Clear(recorder)

	cookie := recorder.Result().Cookies()[0]
	if cookie.MaxAge != -1 {
		t.Errorf("clear cookie MaxAge = %d", cookie.MaxAge)
	}
	raw := recorder.Header().Get("Set-Cookie")
	for _, want := range []string{"Domain=surma.technology", "Path=/", "Max-Age=0"} {
		if !strings.Contains(raw, want) {
			t.Errorf("Set-Cookie %q lacks %q", raw, want)
		}
	}
}

func TestSessionCreateRejectsEmptyIdentity(t *testing.T) {
	manager := newTestManager()
	if err := manager.Create(httptest.NewRecorder(), &User{Username: "x"}); err == nil {
		t.Fatal("user without stable identity accepted")
	}
}

// --- helpers that exercise the jwt library directly ---

const issuerOther = "someone-else"

func freshRegisteredClaims(d time.Duration) jwtRegisteredClaimsShape {
	return registeredClaims(sessionIssuer, d)
}

func TestDerivePurposeKeySeparatesPurposes(t *testing.T) {
	secret := []byte("shared-secret")
	a := DerivePurposeKey(secret, "purpose-a")
	b := DerivePurposeKey(secret, "purpose-b")
	if string(a) == string(b) {
		t.Fatal("distinct purposes derived the same key")
	}
	if string(DerivePurposeKey(secret, "purpose-a")) != string(a) {
		t.Fatal("key derivation is not deterministic")
	}
	if strings.Contains(string(a), "shared-secret") {
		t.Fatal("derived key leaks the input secret")
	}
}
