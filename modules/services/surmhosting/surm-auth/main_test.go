package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
	"github.com/surma/surm-auth/policy"
)

// TestGitHubEndpointsFallbackAndOverrides covers the endpoint seam:
// unset fields select the public GitHub endpoints, and configured
// overrides replace exactly the fields they name.
func TestGitHubEndpointsFallbackAndOverrides(t *testing.T) {
	cfg := &config.Config{}
	endpoints := githubEndpoints(cfg)
	if endpoints.AuthURL != "https://github.com/login/oauth/authorize" {
		t.Errorf("default auth URL = %q", endpoints.AuthURL)
	}
	if endpoints.TokenURL != "https://github.com/login/oauth/access_token" {
		t.Errorf("default token URL = %q", endpoints.TokenURL)
	}
	if endpoints.UserURL != "https://api.github.com/user" {
		t.Errorf("default user URL = %q", endpoints.UserURL)
	}
	if endpoints.UsersAPIURL != "https://api.github.com/users" {
		t.Errorf("default users API URL = %q", endpoints.UsersAPIURL)
	}

	cfg.Providers.GitHub.AuthURL = "http://127.0.0.1:1/authorize"
	cfg.Providers.GitHub.TokenURL = "http://127.0.0.1:1/token"
	cfg.Providers.GitHub.UserURL = "http://127.0.0.1:1/user"
	cfg.Providers.GitHub.UsersAPIURL = "http://127.0.0.1:1/users"
	endpoints = githubEndpoints(cfg)
	if endpoints.AuthURL != "http://127.0.0.1:1/authorize" {
		t.Errorf("override auth URL = %q", endpoints.AuthURL)
	}
	if endpoints.TokenURL != "http://127.0.0.1:1/token" {
		t.Errorf("override token URL = %q", endpoints.TokenURL)
	}
	if endpoints.UserURL != "http://127.0.0.1:1/user" {
		t.Errorf("override user URL = %q", endpoints.UserURL)
	}
	if endpoints.UsersAPIURL != "http://127.0.0.1:1/users" {
		t.Errorf("override users API URL = %q", endpoints.UsersAPIURL)
	}
}

// TestSeedResolutionFailureLeavesNoPartialState covers the initial
// seed import from empty state: when one seed username fails to
// resolve, resolution must fail before any commit. No policy file,
// grant, or import marker may exist afterwards.
func TestSeedResolutionFailureLeavesNoPartialState(t *testing.T) {
	root := t.TempDir()
	cfg := loadSeedConfig(t, root, []string{"surma", "ghost"})

	store, err := policy.Open(cfg.Policy.File)
	if err != nil {
		t.Fatal(err)
	}

	// The real provider points at a local test server: "surma"
	// resolves, "ghost" does not. No request leaves the loopback.
	provider := localProvider(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/users/ghost") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte(`{"id": 2000, "login": "surma"}`))
	})

	// The same ordering as main: resolveSeeds runs before Bootstrap.
	seeds, err := resolveSeeds(cfg, provider, store)
	if err == nil {
		t.Fatalf("seed resolution succeeded despite an unresolved user: %+v", seeds)
	}
	if !strings.Contains(err.Error(), "packapp") {
		t.Errorf("resolution error does not name the app: %v", err)
	}

	// The failed import left no policy file and no partial state.
	if _, err := os.Stat(cfg.Policy.File); !os.IsNotExist(err) {
		t.Error("a failed seed import created a policy file")
	}
	snapshot := store.Snapshot()
	if len(snapshot.Grants) != 0 {
		t.Errorf("partial seed grants leaked: %+v", snapshot.Grants)
	}
	if len(snapshot.Users) != 0 {
		t.Errorf("partial users leaked: %+v", snapshot.Users)
	}
	if store.SeedImported("packapp") {
		t.Error("import marker set despite failed resolution")
	}
}

// TestSeedImportCommitIsAtomic covers the successful initial import
// from empty state: one commit holds bootstrap admins, all seed
// grants, and the import marker, and everything survives a restart.
func TestSeedImportCommitIsAtomic(t *testing.T) {
	root := t.TempDir()
	cfg := loadSeedConfig(t, root, []string{"surma", "octocat"})

	store, err := policy.Open(cfg.Policy.File)
	if err != nil {
		t.Fatal(err)
	}
	provider := localProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch strings.TrimPrefix(r.URL.Path, "/users/") {
		case "surma":
			_, _ = w.Write([]byte(`{"id": 2000, "login": "surma"}`))
		case "octocat":
			_, _ = w.Write([]byte(`{"id": 2001, "login": "octocat"}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	})

	seeds, err := resolveSeeds(cfg, provider, store)
	if err != nil {
		t.Fatalf("seed resolution failed: %v", err)
	}
	if len(seeds["packapp"]) != 2 {
		t.Fatalf("resolved seeds = %d, want 2", len(seeds["packapp"]))
	}

	// The same commit as main's startup sequence.
	admins := make([]policy.Admin, 0, len(cfg.BootstrapAdmins))
	for _, a := range cfg.BootstrapAdmins {
		admins = append(admins, policy.Admin{Provider: a.Provider, ID: a.ID})
	}
	if err := store.Bootstrap(admins, seeds); err != nil {
		t.Fatalf("bootstrap failed: %v", err)
	}

	// The single commit is persisted: a restart reloads admins,
	// grants, and the marker together.
	reopened, err := policy.Open(cfg.Policy.File)
	if err != nil {
		t.Fatalf("restart failed: %v", err)
	}
	if len(reopened.Snapshot().Grants["packapp"]) != 2 {
		t.Errorf("persisted seed grants = %+v", reopened.Snapshot().Grants["packapp"])
	}
	if !reopened.SeedImported("packapp") {
		t.Error("import marker not persisted")
	}
	if admin, _ := reopened.IsAdmin("github", "1000"); !admin {
		t.Error("bootstrap admin not persisted")
	}
}

// TestSeedImportSkipsMarkedApps proves that a completed import marker
// blocks resolution entirely: the provider is never contacted for a
// marked app, so a temporarily unresolvable username cannot block
// readiness after the marker exists.
func TestSeedImportSkipsMarkedApps(t *testing.T) {
	root := t.TempDir()
	cfg := loadSeedConfig(t, root, []string{"surma"})

	store, err := policy.Open(cfg.Policy.File)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Bootstrap(nil, map[string][]*auth.User{"packapp": {}}); err != nil {
		t.Fatal(err)
	}

	provider := localProvider(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("resolution ran for an app with a completed marker")
		w.WriteHeader(http.StatusNotFound)
	})

	seeds, err := resolveSeeds(cfg, provider, store)
	if err != nil {
		t.Fatalf("a completed marker blocked readiness: %v", err)
	}
	if len(seeds) != 0 {
		t.Errorf("seeds resolved for a marked app: %+v", seeds)
	}
}

// --- helpers ---

// loadSeedConfig writes a valid v2 config for one allowlisted app
// with the given seed users and returns the loaded configuration.
func loadSeedConfig(t *testing.T, root string, seedUsers []string) *config.Config {
	t.Helper()
	seedYAML := "    seed_users: []\n"
	if len(seedUsers) > 0 {
		quoted := make([]string, len(seedUsers))
		for i, u := range seedUsers {
			quoted[i] = fmt.Sprintf("%q", u)
		}
		seedYAML = "    seed_users: [" + strings.Join(quoted, ", ") + "]\n"
	}

	raw := fmt.Sprintf(`
version: 2
server:
  address: "127.0.0.1:0"
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
%s`,
		filepath.Join(root, "cookie-secret"),
		filepath.Join(root, "policy.json"),
		filepath.Join(root, "audit.log"),
		filepath.Join(root, "github-client-id"),
		filepath.Join(root, "github-client-secret"),
		seedYAML)

	path := filepath.Join(root, "config.yaml")
	if err := os.WriteFile(path, []byte(raw), 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("seed test config invalid: %v", err)
	}
	return cfg
}

// localProvider builds the real GitHub provider against a local test
// server, so username resolution never contacts github.com.
func localProvider(t *testing.T, handler http.HandlerFunc) *auth.GitHubProvider {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return auth.NewGitHubProvider("local-id", "local-secret", "https://auth.surma.technology/callback", auth.GitHubEndpoints{
		AuthURL:     server.URL + "/authorize",
		TokenURL:    server.URL + "/token",
		UserURL:     server.URL + "/user",
		UsersAPIURL: server.URL + "/users",
	}, server.Client())
}
