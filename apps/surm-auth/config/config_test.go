package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validConfig = `
version: 2
server:
  address: "0.0.0.0:8080"
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
  file: "/var/lib/surm-auth/policy.json"
audit:
  file: "/var/lib/surm-auth/audit.log"
providers:
  github:
    client_id_file: "/tmp/github-client-id"
    client_secret_file: "/tmp/github-client-secret"
bootstrap_admins:
  - provider: "github"
    id: "12345"
apps:
  hedgedoc2:
    mode: "allowlist"
    domains: ["hedgedoc.apps.surma.technology", "hedgedoc.surma.technology"]
    seed_users: ["surma"]
  public-brain:
    mode: "public"
    domains: ["public-brain.apps.surma.technology"]
  rss:
    mode: "internal"
    domains: []
`

func loadFromString(t *testing.T, input string) (*Config, error) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte(input), 0600); err != nil {
		t.Fatal(err)
	}
	return Load(path)
}

func TestLoadValidConfig(t *testing.T) {
	cfg, err := loadFromString(t, validConfig)
	if err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
	if cfg.Version != 2 {
		t.Errorf("version = %d, want 2", cfg.Version)
	}
	if cfg.Session.CookieName != "_surm_auth2" {
		t.Errorf("cookie_name = %q", cfg.Session.CookieName)
	}
	if len(cfg.Apps) != 3 {
		t.Errorf("apps = %d, want 3", len(cfg.Apps))
	}
	hedgedoc := cfg.Apps["hedgedoc2"]
	if hedgedoc.Mode != ModeAllowlist || len(hedgedoc.SeedUsers) != 1 {
		t.Errorf("hedgedoc2 app = %+v", hedgedoc)
	}
	if len(cfg.BootstrapAdmins) != 1 || cfg.BootstrapAdmins[0].ID != "12345" {
		t.Errorf("bootstrap admins = %+v", cfg.BootstrapAdmins)
	}
}

func TestLoadRejectsLegacyV1Config(t *testing.T) {
	legacy := `
server:
  address: "0.0.0.0:8080"
  base_url: "https://auth.surma.technology"
oauth:
  github:
    client_id_file: "/tmp/id"
session:
  cookie_name: "_surm_auth"
  cookie_domain: ".surma.technology"
  cookie_secret_file: "/tmp/cookie"
  duration: "168h"
apps:
  hedgedoc:
    allowed_users: ["surma"]
`
	_, err := loadFromString(t, legacy)
	if err == nil {
		t.Fatal("legacy v1 config accepted")
	}
	if !strings.Contains(err.Error(), "oauth") || !strings.Contains(err.Error(), "v2") {
		t.Errorf("error should mention legacy oauth key and v2 migration, got: %v", err)
	}

	_, err = loadFromString(t, strings.Replace(legacy, "oauth:", "other: #\n  github:", 1))
	_ = err // covered by unknown-field case below
}

func TestLoadRejectsLegacyAllowedUsers(t *testing.T) {
	legacy := `
version: 2
server:
  address: "0.0.0.0:8080"
  base_url: "https://auth.surma.technology"
  auth_domains: ["auth.surma.technology"]
session:
  cookie_name: "_surm_auth2"
  cookie_domain: ".surma.technology"
  cookie_secret_file: "/tmp/c"
  duration: "1h"
policy:
  file: "/tmp/policy.json"
audit:
  file: "/tmp/audit.log"
providers:
  github:
    client_id_file: "/tmp/id"
    client_secret_file: "/tmp/secret"
apps:
  hedgedoc:
    mode: "allowlist"
    domains: ["hedgedoc.apps.surma.technology"]
    allowed_users: ["surma"]
`
	_, err := loadFromString(t, legacy)
	if err == nil {
		t.Fatal("legacy allowed_users accepted")
	}
	if !strings.Contains(err.Error(), "allowed_users") {
		t.Errorf("error should mention allowed_users, got: %v", err)
	}
}

func TestLoadRejectsUnknownField(t *testing.T) {
	_, err := loadFromString(t, validConfig+"\nunknown_top_level: true\n")
	if err == nil {
		t.Fatal("unknown top-level field accepted")
	}
}

func TestLoadRejectsWrongVersion(t *testing.T) {
	_, err := loadFromString(t, strings.Replace(validConfig, "version: 2", "version: 1", 1))
	if err == nil {
		t.Fatal("version 1 accepted")
	}
}

func TestLoadRejectsBadBaseURL(t *testing.T) {
	httpBase := strings.Replace(validConfig, "https://auth.surma.technology", "http://auth.surma.technology", 1)
	if _, err := loadFromString(t, httpBase); err == nil {
		t.Error("HTTP base URL accepted")
	}

	unrelated := strings.Replace(validConfig, `- "auth.surma.technology"`, `- "other.example.com"`, 1)
	if _, err := loadFromString(t, unrelated); err == nil {
		t.Error("base URL outside auth_domains accepted")
	}
}

func TestLoadRejectsBadDuration(t *testing.T) {
	bad := strings.Replace(validConfig, `duration: "168h"`, `duration: "forever"`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("invalid duration accepted")
	}
}

func TestLoadRejectsUnknownMode(t *testing.T) {
	bad := strings.Replace(validConfig, `mode: "public"`, `mode: "open"`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("unknown mode accepted")
	}
}

func TestLoadRejectsPublicAppWithoutDomains(t *testing.T) {
	bad := strings.Replace(validConfig, `    mode: "public"
    domains: ["public-brain.apps.surma.technology"]`, `    mode: "public"`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("public app without domains accepted")
	}
}

func TestLoadRejectsInternalAppWithDomains(t *testing.T) {
	bad := strings.Replace(validConfig, `  rss:
    mode: "internal"
    domains: []`, `  rss:
    mode: "internal"
    domains: ["rss.apps.surma.technology"]`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("internal app with domains accepted")
	}
}

func TestLoadRejectsSeedUsersOnNonAllowlist(t *testing.T) {
	bad := strings.Replace(validConfig, `    domains: ["public-brain.apps.surma.technology"]`,
		`    domains: ["public-brain.apps.surma.technology"]
    seed_users: ["surma"]`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("seed users on public app accepted")
	}
}

func TestLoadRejectsDuplicateDomainAcrossApps(t *testing.T) {
	bad := strings.Replace(validConfig, `    domains: ["public-brain.apps.surma.technology"]`,
		`    domains: ["public-brain.apps.surma.technology", "hedgedoc.apps.surma.technology"]`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("duplicate domain across apps accepted")
	}
}

func TestLoadRejectsPlaceholderBootstrapID(t *testing.T) {
	bad := strings.Replace(validConfig, `id: "12345"`, `id: "<verified-numeric-id>"`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("placeholder bootstrap ID accepted")
	}
	empty := strings.Replace(validConfig, `id: "12345"`, `id: ""`, 1)
	if _, err := loadFromString(t, empty); err == nil {
		t.Error("empty bootstrap ID accepted")
	}
}

func TestLoadRejectsEmptyPolicyPath(t *testing.T) {
	bad := strings.Replace(validConfig, `  file: "/var/lib/surm-auth/policy.json"`, `  file: ""`, 1)
	if _, err := loadFromString(t, bad); err == nil {
		t.Error("empty policy path accepted")
	}
}

func TestLoadSecrets(t *testing.T) {
	dir := t.TempDir()
	write := func(name, value string) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte(value+"\n"), 0600); err != nil {
			t.Fatal(err)
		}
		return path
	}
	idPath := write("github-client-id", "Iv1.clientid")
	secretPath := write("github-client-secret", "ghp_secret")
	cookiePath := write("cookie-secret", strings.Repeat("x", 48))

	cfg, err := loadFromString(t, validConfig)
	if err != nil {
		t.Fatal(err)
	}
	cfg.Providers.GitHub.ClientIDFile = idPath
	cfg.Providers.GitHub.ClientSecretFile = secretPath
	cfg.Session.CookieSecretFile = cookiePath

	if err := cfg.LoadSecrets(); err != nil {
		t.Fatalf("LoadSecrets failed: %v", err)
	}
	if cfg.Providers.GitHub.ClientID != "Iv1.clientid" {
		t.Errorf("client ID = %q", cfg.Providers.GitHub.ClientID)
	}
	if cfg.Providers.GitHub.ClientSecret != "ghp_secret" {
		t.Errorf("client secret = %q", cfg.Providers.GitHub.ClientSecret)
	}
	if len(cfg.Session.CookieSecret) != 48 {
		t.Errorf("cookie secret length = %d", len(cfg.Session.CookieSecret))
	}
}

func TestLoadSecretsMissingFile(t *testing.T) {
	cfg, err := loadFromString(t, validConfig)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfg.LoadSecrets(); err == nil {
		t.Fatal("LoadSecrets succeeded with missing secret files")
	}
}

func TestLoadSecretsShortCookieSecret(t *testing.T) {
	dir := t.TempDir()
	write := func(name, value string) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte(value), 0600); err != nil {
			t.Fatal(err)
		}
		return path
	}
	cfg, err := loadFromString(t, validConfig)
	if err != nil {
		t.Fatal(err)
	}
	cfg.Providers.GitHub.ClientIDFile = write("id", "clientid")
	cfg.Providers.GitHub.ClientSecretFile = write("secret", "secret")
	cfg.Session.CookieSecretFile = write("cookie", "too-short")

	if err := cfg.LoadSecrets(); err == nil {
		t.Fatal("short cookie secret accepted")
	}
}
