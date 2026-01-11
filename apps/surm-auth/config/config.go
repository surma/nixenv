package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server struct {
		Address string `yaml:"address"`
		BaseURL string `yaml:"base_url"`
	} `yaml:"server"`

	OAuth struct {
		GitHub struct {
			ClientIDFile     string `yaml:"client_id_file"`
			ClientSecretFile string `yaml:"client_secret_file"`
			ClientID         string `yaml:"-"` // Loaded from file
			ClientSecret     string `yaml:"-"` // Loaded from file
		} `yaml:"github"`
	} `yaml:"oauth"`

	Session struct {
		CookieName       string `yaml:"cookie_name"`
		CookieDomain     string `yaml:"cookie_domain"`
		CookieSecretFile string `yaml:"cookie_secret_file"`
		CookieSecret     string `yaml:"-"` // Loaded from file
		CookieSecure     bool   `yaml:"cookie_secure"`
		Duration         string `yaml:"duration"`
	} `yaml:"session"`

	Apps map[string]AppConfig `yaml:"apps"`
}

type AppConfig struct {
	AllowedUsers []string `yaml:"allowed_users"`
}

// Load reads and parses the config file
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	return &cfg, nil
}

// LoadSecrets reads secret values from files specified in the config
func (c *Config) LoadSecrets() error {
	// Load GitHub client ID
	clientID, err := os.ReadFile(c.OAuth.GitHub.ClientIDFile)
	if err != nil {
		return fmt.Errorf("failed to read GitHub client ID: %w", err)
	}
	c.OAuth.GitHub.ClientID = string(clientID)

	// Load GitHub client secret
	clientSecret, err := os.ReadFile(c.OAuth.GitHub.ClientSecretFile)
	if err != nil {
		return fmt.Errorf("failed to read GitHub client secret: %w", err)
	}
	c.OAuth.GitHub.ClientSecret = string(clientSecret)

	// Load cookie secret
	cookieSecret, err := os.ReadFile(c.Session.CookieSecretFile)
	if err != nil {
		return fmt.Errorf("failed to read cookie secret: %w", err)
	}
	c.Session.CookieSecret = string(cookieSecret)

	return nil
}
