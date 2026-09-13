package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newTestProvider builds a GitHubProvider against httptest endpoints.
func newTestProvider(t *testing.T, handler http.Handler) (*GitHubProvider, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	endpoints := GitHubEndpoints{
		AuthURL:     server.URL + "/login/oauth/authorize",
		TokenURL:    server.URL + "/login/oauth/access_token",
		UserURL:     server.URL + "/user",
		UsersAPIURL: server.URL + "/users",
	}
	provider := NewGitHubProvider("client-id", "client-secret", "https://auth.surma.technology/callback", endpoints, server.Client())
	return provider, server
}

func githubHandler(t *testing.T) http.Handler {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/login/oauth/access_token", func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("bad token request: %v", err)
		}
		if r.PostFormValue("code") != "the-code" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"tok","token_type":"bearer"}`))
	})
	mux.HandleFunc("/user", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer tok" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":987654,"login":"surma","email":"surma@example.com","avatar_url":"https://avatars.example/surma.png"}`))
	})
	mux.HandleFunc("/users/", func(w http.ResponseWriter, r *http.Request) {
		login := strings.TrimPrefix(r.URL.Path, "/users/")
		if login == "surma" {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":987654,"login":"surma","email":null,"avatar_url":"https://avatars.example/surma.png"}`))
			return
		}
		http.NotFound(w, r)
	})
	return mux
}

func TestGitHubExchange(t *testing.T) {
	provider, _ := newTestProvider(t, githubHandler(t))

	user, err := provider.Exchange("the-code")
	if err != nil {
		t.Fatalf("Exchange failed: %v", err)
	}
	if user.Provider != "github" {
		t.Errorf("provider = %q", user.Provider)
	}
	if user.ID != "987654" {
		t.Errorf("stable ID = %q, want numeric 987654", user.ID)
	}
	if user.Username != "surma" {
		t.Errorf("username = %q", user.Username)
	}
	if user.Email != "surma@example.com" {
		t.Errorf("email = %q", user.Email)
	}
	if user.Subject() != "github:987654" {
		t.Errorf("subject = %q", user.Subject())
	}
}

func TestGitHubExchangeBadCode(t *testing.T) {
	provider, _ := newTestProvider(t, githubHandler(t))
	if _, err := provider.Exchange("wrong-code"); err == nil {
		t.Fatal("exchange with wrong code succeeded")
	}
}

func TestGitHubAuthURL(t *testing.T) {
	provider, _ := newTestProvider(t, githubHandler(t))
	url := provider.AuthURL("state-token")
	if !strings.HasPrefix(url, "https://github.com") && !strings.Contains(url, "/login/oauth/authorize") {
		t.Errorf("auth URL = %q", url)
	}
	if !strings.Contains(url, "client_id=client-id") || !strings.Contains(url, "state=state-token") {
		t.Errorf("auth URL = %q", url)
	}
}

func TestGitHubResolveUsername(t *testing.T) {
	provider, _ := newTestProvider(t, githubHandler(t))

	user, err := provider.ResolveUsername("surma")
	if err != nil {
		t.Fatalf("ResolveUsername failed: %v", err)
	}
	if user.ID != "987654" || user.Username != "surma" || user.Provider != "github" {
		t.Errorf("resolved user = %+v", user)
	}

	// Unresolved users return an error and no user.
	if _, err := provider.ResolveUsername("ghost"); err == nil {
		t.Error("resolving unknown username succeeded")
	}
	if _, err := provider.ResolveUsername(""); err == nil {
		t.Error("resolving empty username succeeded")
	}
}

func TestGitHubRejectsNonNumericID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"not-a-number","login":"surma"}`))
	}))
	defer server.Close()

	endpoints := GitHubEndpoints{
		AuthURL:     server.URL,
		TokenURL:    server.URL + "/token",
		UserURL:     server.URL + "/user",
		UsersAPIURL: server.URL + "/users",
	}
	provider := NewGitHubProvider("id", "secret", "https://cb", endpoints, server.Client())

	// json.Number accepts any numeric-shaped JSON; verify the
	// placeholder rejection rule via an object id.
	if _, err := provider.ResolveUsername("surma"); err == nil {
		// "not-a-number" is a JSON string, not a number, so decoding
		// into json.Number must fail.
		t.Fatal("non-numeric ID accepted")
	}
}

func TestGitHubUserEndpointError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	endpoints := DefaultGitHubEndpoints()
	endpoints.AuthURL = server.URL
	endpoints.TokenURL = server.URL + "/token"
	endpoints.UserURL = server.URL + "/user"
	endpoints.UsersAPIURL = server.URL + "/users"
	provider := NewGitHubProvider("id", "secret", "https://cb", endpoints, server.Client())

	if _, err := provider.Exchange("code"); err == nil {
		t.Error("exchange against failing user endpoint succeeded")
	}
}

func TestGitHubTokenResponseJSON(t *testing.T) {
	// Guard the token endpoint contract: the exchange succeeds against
	// a JSON-only token endpoint.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "tok"})
	}))
	defer server.Close()

	endpoints := DefaultGitHubEndpoints()
	endpoints.TokenURL = server.URL + "/token"
	endpoints.UserURL = server.URL + "/missing-user"
	provider := NewGitHubProvider("id", "secret", "https://cb", endpoints, server.Client())

	_, err := provider.Exchange("code")
	if err == nil {
		t.Fatal("expected the user fetch to fail on this server")
	}
	if strings.Contains(err.Error(), "token") && strings.Contains(err.Error(), "exchange") {
		t.Fatalf("token exchange itself failed: %v", err)
	}
}
