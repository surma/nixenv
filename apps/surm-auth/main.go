package main

import (
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
	"github.com/surma/surm-auth/handlers"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "/etc/surm-auth/config.yaml", "Path to config file")
	flag.Parse()

	// Setup logging
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// Load configuration
	slog.Info("loading configuration", "path", *configPath)
	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	// Load secrets from files
	slog.Info("loading secrets")
	if err := cfg.LoadSecrets(); err != nil {
		slog.Error("failed to load secrets", "error", err)
		os.Exit(1)
	}

	// Parse session duration
	duration, err := time.ParseDuration(cfg.Session.Duration)
	if err != nil {
		slog.Error("invalid session duration", "duration", cfg.Session.Duration, "error", err)
		os.Exit(1)
	}

	// Initialize GitHub OAuth provider
	slog.Info("initializing GitHub OAuth provider")
	provider := auth.NewGitHubProvider(
		cfg.OAuth.GitHub.ClientID,
		cfg.OAuth.GitHub.ClientSecret,
		cfg.Server.BaseURL+"/callback",
	)

	// Initialize session manager
	slog.Info("initializing session manager",
		"cookie_name", cfg.Session.CookieName,
		"cookie_domain", cfg.Session.CookieDomain,
		"duration", duration)
	sessionManager := auth.NewManager(
		[]byte(cfg.Session.CookieSecret),
		cfg.Session.CookieName,
		cfg.Session.CookieDomain,
		cfg.Session.CookieSecure,
		duration,
	)

	// Setup HTTP routes
	http.HandleFunc("/auth", handlers.AuthHandler(cfg, sessionManager))
	http.HandleFunc("/login", handlers.LoginHandler(provider, []byte(cfg.Session.CookieSecret)))
	http.HandleFunc("/callback", handlers.CallbackHandler(provider, sessionManager, cfg, []byte(cfg.Session.CookieSecret)))
	http.HandleFunc("/logout", handlers.LogoutHandler(sessionManager, cfg.Server.BaseURL))
	
	// Health check endpoint
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	// Log configured apps
	slog.Info("configured apps", "count", len(cfg.Apps))
	for appName, appCfg := range cfg.Apps {
		slog.Info("app configured",
			"name", appName,
			"allowed_users", appCfg.AllowedUsers)
	}

	// Start HTTP server
	slog.Info("starting server", "address", cfg.Server.Address, "base_url", cfg.Server.BaseURL)
	if err := http.ListenAndServe(cfg.Server.Address, nil); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}
