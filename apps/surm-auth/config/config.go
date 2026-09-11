// Package config implements strict loading and validation of the
// surm-auth v2 configuration file.
package config

import (
	"bytes"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// CurrentVersion is the only supported configuration version.
const CurrentVersion = 2

// App access modes.
const (
	ModeInternal      = "internal"
	ModePublic        = "public"
	ModeAuthenticated = "authenticated"
	ModeAllowlist     = "allowlist"
)

// Config is the complete v2 configuration.
type Config struct {
	Version         int                `yaml:"version"`
	Server          ServerConfig       `yaml:"server"`
	Session         SessionConfig      `yaml:"session"`
	Policy          PolicyConfig       `yaml:"policy"`
	Audit           AuditConfig        `yaml:"audit"`
	Providers       ProvidersConfig    `yaml:"providers"`
	BootstrapAdmins []BootstrapAdmin   `yaml:"bootstrap_admins"`
	Apps            map[string]AppConf `yaml:"apps"`
}

// ServerConfig describes the HTTP server and canonical auth URLs.
type ServerConfig struct {
	Address     string   `yaml:"address"`
	BaseURL     string   `yaml:"base_url"`
	AuthDomains []string `yaml:"auth_domains"`
}

// SessionConfig describes the v2 session cookie.
type SessionConfig struct {
	CookieName       string `yaml:"cookie_name"`
	CookieDomain     string `yaml:"cookie_domain"`
	CookieSecretFile string `yaml:"cookie_secret_file"`
	CookieSecret     string `yaml:"-"`
	CookieSecure     bool   `yaml:"cookie_secure"`
	Duration         string `yaml:"duration"`
}

// PolicyConfig points at the persistent policy file.
type PolicyConfig struct {
	File string `yaml:"file"`
}

// AuditConfig points at the audit log file.
type AuditConfig struct {
	File string `yaml:"file"`
}

// ProvidersConfig declares the configured OAuth providers.
type ProvidersConfig struct {
	GitHub GitHubConfig `yaml:"github"`
}

// GitHubConfig holds GitHub provider file references. The secret values
// are loaded through LoadSecrets and never serialized. The endpoint
// fields are an explicit test seam: empty values select the public
// GitHub endpoints, and production configuration must leave them
// unset.
type GitHubConfig struct {
	ClientIDFile     string `yaml:"client_id_file"`
	ClientSecretFile string `yaml:"client_secret_file"`
	ClientID         string `yaml:"-"`
	ClientSecret     string `yaml:"-"`
	AuthURL          string `yaml:"auth_url"`
	TokenURL         string `yaml:"token_url"`
	UserURL          string `yaml:"user_url"`
	UsersAPIURL      string `yaml:"users_api_url"`
}

// BootstrapAdmin is a Nix-owned admin identity. The ID must be the
// stable provider ID, never a username.
type BootstrapAdmin struct {
	Provider string `yaml:"provider"`
	ID       string `yaml:"id"`
}

// AppConf is one logical application and its access policy.
type AppConf struct {
	Mode      string   `yaml:"mode"`
	Domains   []string `yaml:"domains"`
	SeedUsers []string `yaml:"seed_users"`
}

// Load reads, parses, and validates the configuration file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	if err := checkLegacyKeys(data); err != nil {
		return nil, err
	}

	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)

	var cfg Config
	if err := dec.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// checkLegacyKeys rejects v1 configuration shapes with a migration
// error instead of a generic unknown-field error.
func checkLegacyKeys(data []byte) error {
	var raw map[string]any
	dec := yaml.NewDecoder(bytes.NewReader(data))
	if err := dec.Decode(&raw); err != nil {
		return nil // Malformed YAML is reported by the strict decode below.
	}

	if _, ok := raw["oauth"]; ok {
		return fmt.Errorf("legacy v1 key 'oauth:' is not supported by surm-auth v2; migrate to providers.github (see auth-rework section 5.1)")
	}
	if _, ok := raw["allowed_users"]; ok {
		return fmt.Errorf("legacy v1 key 'allowed_users:' is not supported by surm-auth v2; migrate to logical apps with access modes (see auth-rework section 5.1)")
	}
	if apps, ok := raw["apps"].(map[string]any); ok {
		for name, v := range apps {
			if entry, ok := v.(map[string]any); ok {
				if _, ok := entry["allowed_users"]; ok {
					return fmt.Errorf("legacy v1 key 'allowed_users:' in app %q is not supported by surm-auth v2; migrate to access modes and seed users (see auth-rework section 5.1)", name)
				}
			}
		}
	}
	return nil
}

// Validate performs strict v2 validation. It returns a descriptive
// error for every violated rule so startup fails cleanly.
func (c *Config) Validate() error {
	if c.Version != CurrentVersion {
		return fmt.Errorf("configuration version must be %d, got %d", CurrentVersion, c.Version)
	}

	if err := c.Server.validate(); err != nil {
		return fmt.Errorf("server: %w", err)
	}
	if err := c.Session.validate(); err != nil {
		return fmt.Errorf("session: %w", err)
	}
	if c.Policy.File == "" {
		return fmt.Errorf("policy.file must not be empty")
	}
	if c.Audit.File == "" {
		return fmt.Errorf("audit.file must not be empty")
	}
	if c.Providers.GitHub.ClientIDFile == "" || c.Providers.GitHub.ClientSecretFile == "" {
		return fmt.Errorf("providers.github: client_id_file and client_secret_file must not be empty")
	}

	if err := c.Providers.GitHub.validateEndpoints(); err != nil {
		return fmt.Errorf("providers.github: %w", err)
	}

	for i, admin := range c.BootstrapAdmins {
		if admin.Provider == "" {
			return fmt.Errorf("bootstrap_admins[%d]: provider must not be empty", i)
		}
		if err := validateStableID(admin.ID); err != nil {
			return fmt.Errorf("bootstrap_admins[%d]: %w", i, err)
		}
	}

	seenDomains := map[string]string{}
	for name, app := range c.Apps {
		if err := app.validate(); err != nil {
			return fmt.Errorf("apps.%s: %w", name, err)
		}
		for _, d := range app.Domains {
			if other, ok := seenDomains[d]; ok {
				return fmt.Errorf("apps.%s: domain %q is already used by app %q", name, d, other)
			}
			seenDomains[d] = name
		}
	}

	return nil
}

func (s *ServerConfig) validate() error {
	if s.Address == "" {
		return fmt.Errorf("address must not be empty")
	}
	u, err := url.Parse(s.BaseURL)
	if err != nil {
		return fmt.Errorf("base_url %q is not a valid URL: %w", s.BaseURL, err)
	}
	if u.Scheme != "https" {
		return fmt.Errorf("base_url %q must use HTTPS", s.BaseURL)
	}
	if u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return fmt.Errorf("base_url %q must be a bare origin", s.BaseURL)
	}
	host := normalizeHost(u.Host)
	if len(s.AuthDomains) == 0 {
		return fmt.Errorf("auth_domains must not be empty")
	}
	found := false
	for _, d := range s.AuthDomains {
		if err := validateDomain(d); err != nil {
			return fmt.Errorf("auth_domains: %w", err)
		}
		if normalizeHost(d) == host {
			found = true
		}
	}
	if !found {
		return fmt.Errorf("base_url host %q must belong to auth_domains", host)
	}
	return nil
}

func (s *SessionConfig) validate() error {
	if s.CookieName == "" {
		return fmt.Errorf("cookie_name must not be empty")
	}
	if s.CookieDomain == "" {
		return fmt.Errorf("cookie_domain must not be empty")
	}
	if s.CookieSecretFile == "" {
		return fmt.Errorf("cookie_secret_file must not be empty")
	}
	d, err := time.ParseDuration(s.Duration)
	if err != nil {
		return fmt.Errorf("duration %q is not a valid duration: %w", s.Duration, err)
	}
	if d <= 0 {
		return fmt.Errorf("duration %q must be positive", s.Duration)
	}
	return nil
}

// validateEndpoints requires every configured endpoint override to be
// an absolute HTTP(S) URL. Empty fields stay untouched and select the
// GitHub defaults.
func (g GitHubConfig) validateEndpoints() error {
	for field, value := range map[string]string{
		"auth_url":      g.AuthURL,
		"token_url":     g.TokenURL,
		"user_url":      g.UserURL,
		"users_api_url": g.UsersAPIURL,
	} {
		if value == "" {
			continue
		}
		u, err := url.Parse(value)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return fmt.Errorf("%s %q must be an absolute HTTP(S) URL", field, value)
		}
	}
	return nil
}

func (a *AppConf) validate() error {
	switch a.Mode {
	case ModeInternal:
		if len(a.Domains) != 0 {
			return fmt.Errorf("internal apps must not declare domains")
		}
	case ModePublic, ModeAuthenticated, ModeAllowlist:
		if len(a.Domains) == 0 {
			return fmt.Errorf("%s apps must declare at least one domain", a.Mode)
		}
	default:
		return fmt.Errorf("mode must be one of internal, public, authenticated, allowlist (got %q)", a.Mode)
	}
	if a.Mode != ModeAllowlist && len(a.SeedUsers) != 0 {
		return fmt.Errorf("seed users are only valid on %s apps", ModeAllowlist)
	}
	for _, d := range a.Domains {
		if err := validateDomain(d); err != nil {
			return err
		}
	}
	return nil
}

// validateStableID rejects empty and placeholder bootstrap IDs.
func validateStableID(id string) error {
	if id == "" {
		return fmt.Errorf("id must not be empty")
	}
	lower := strings.ToLower(id)
	if strings.Contains(id, "<") || strings.Contains(id, ">") || strings.Contains(lower, "placeholder") {
		return fmt.Errorf("id %q looks like a placeholder; use the verified stable provider ID", id)
	}
	return nil
}

// validateDomain requires a bare hostname without scheme, port, path,
// userinfo, or whitespace.
func validateDomain(domain string) error {
	if domain == "" {
		return fmt.Errorf("domain must not be empty")
	}
	if domain != strings.TrimSpace(domain) || strings.ContainsAny(domain, " \t\r\n") {
		return fmt.Errorf("domain %q contains whitespace", domain)
	}
	if strings.Contains(domain, "/") || strings.Contains(domain, "@") || strings.Contains(domain, ":") || strings.Contains(domain, "\\") {
		return fmt.Errorf("domain %q must be a bare hostname without scheme, port, path, or userinfo", domain)
	}
	return nil
}

func normalizeHost(host string) string {
	return strings.ToLower(strings.TrimSuffix(host, ":443"))
}

// LoadSecrets reads all secret values from their files and populates
// the non-serialized secret fields. It must run before any provider or
// session constructor consumes them.
func (c *Config) LoadSecrets() error {
	clientID, err := readSecret(c.Providers.GitHub.ClientIDFile)
	if err != nil {
		return fmt.Errorf("failed to read GitHub client ID: %w", err)
	}
	c.Providers.GitHub.ClientID = clientID

	clientSecret, err := readSecret(c.Providers.GitHub.ClientSecretFile)
	if err != nil {
		return fmt.Errorf("failed to read GitHub client secret: %w", err)
	}
	c.Providers.GitHub.ClientSecret = clientSecret

	cookieSecret, err := readSecret(c.Session.CookieSecretFile)
	if err != nil {
		return fmt.Errorf("failed to read cookie secret: %w", err)
	}
	if len(cookieSecret) < 32 {
		return fmt.Errorf("cookie secret must be at least 32 bytes")
	}
	c.Session.CookieSecret = cookieSecret

	return nil
}

func readSecret(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(data))
	if value == "" {
		return "", fmt.Errorf("secret file %s is empty", path)
	}
	return value, nil
}
