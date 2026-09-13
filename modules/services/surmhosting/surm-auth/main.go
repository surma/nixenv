package main

import (
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/auth"
	"github.com/surma/surm-auth/config"
	"github.com/surma/surm-auth/handlers"
	"github.com/surma/surm-auth/policy"
)

func main() {
	configPath := flag.String("config", "/etc/surm-auth/config.yaml", "Path to config file")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// 1. Load and validate the v2 configuration.
	slog.Info("loading configuration", "path", *configPath)
	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	// 2. Load all secrets.
	slog.Info("loading secrets")
	if err := cfg.LoadSecrets(); err != nil {
		slog.Error("failed to load secrets", "error", err)
		os.Exit(1)
	}

	duration, err := time.ParseDuration(cfg.Session.Duration)
	if err != nil {
		slog.Error("invalid session duration", "duration", cfg.Session.Duration, "error", err)
		os.Exit(1)
	}

	// 3. Construct providers and their resolvers. Endpoint overrides
	// are an explicit test seam; production keeps the GitHub defaults.
	provider := auth.NewGitHubProvider(
		cfg.Providers.GitHub.ClientID,
		cfg.Providers.GitHub.ClientSecret,
		cfg.Server.BaseURL+"/callback",
		githubEndpoints(cfg),
		nil,
	)
	providers := map[string]auth.Provider{provider.Name(): provider}

	// 4. Open policy and audit state.
	store, err := policy.Open(cfg.Policy.File)
	if err != nil {
		slog.Error("failed to open policy store", "error", err)
		os.Exit(1)
	}
	auditLog, err := audit.Open(cfg.Audit.File)
	if err != nil {
		slog.Error("failed to open audit log", "error", err)
		os.Exit(1)
	}

	// 5. Resolve only the allowlisted apps without completed seed
	// markers. A resolution failure blocks readiness before any commit.
	seeds, err := resolveSeeds(cfg, provider, store)
	if err != nil {
		slog.Error("failed to resolve seed users", "error", err)
		os.Exit(1)
	}

	// 6. Commit bootstrap admins, initial grants, and import markers
	// atomically.
	admins := make([]policy.Admin, 0, len(cfg.BootstrapAdmins))
	for _, a := range cfg.BootstrapAdmins {
		admins = append(admins, policy.Admin{Provider: a.Provider, ID: a.ID})
	}
	if err := store.Bootstrap(admins, seeds); err != nil {
		slog.Error("failed to commit bootstrap policy", "error", err)
		os.Exit(1)
	}
	for name, users := range seeds {
		if err := auditLog.Record(audit.Event{
			Event:  audit.EventSeedImport,
			Actor:  "bootstrap",
			App:    name,
			Detail: fmt.Sprintf("committed %d seed grants", len(users)),
		}); err != nil {
			slog.Error("failed to write audit event", "error", err)
		}
	}

	// 7. Construct session management, transaction state, handlers, and
	// templates.
	sessions := auth.NewManager(
		[]byte(cfg.Session.CookieSecret),
		cfg.Session.CookieName,
		cfg.Session.CookieDomain,
		cfg.Session.CookieSecure,
		duration,
	)
	transactions := auth.NewTransactions(auth.DefaultTransactionLimit, auth.DefaultTransactionTTL)

	templateDir := os.Getenv("SURM_AUTH_TEMPLATES")
	if templateDir == "" {
		templateDir = "./templates"
	}
	server, err := handlers.New(handlers.Deps{
		Config:    cfg,
		Secret:    []byte(cfg.Session.CookieSecret),
		Providers: providers,
		Sessions:  sessions,
		Tx:        transactions,
		Policy:    store,
		Audit:     auditLog,
	}, templateDir)
	if err != nil {
		slog.Error("failed to construct handlers", "error", err)
		os.Exit(1)
	}

	// 8. Start HTTP and report readiness.
	mux := http.NewServeMux()
	server.Register(mux)

	slog.Info("configured apps", "count", len(cfg.Apps))
	for name, appCfg := range cfg.Apps {
		slog.Info("app configured", "name", name, "mode", appCfg.Mode, "domains", len(appCfg.Domains))
	}

	slog.Info("starting server", "address", cfg.Server.Address, "base_url", cfg.Server.BaseURL)
	if err := http.ListenAndServe(cfg.Server.Address, mux); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}

// githubEndpoints maps the optional configuration endpoint overrides
// onto the provider endpoints. Empty fields fall back to the public
// GitHub endpoints, so production configuration stays unchanged.
func githubEndpoints(cfg *config.Config) auth.GitHubEndpoints {
	endpoints := auth.DefaultGitHubEndpoints()
	gh := cfg.Providers.GitHub
	if gh.AuthURL != "" {
		endpoints.AuthURL = gh.AuthURL
	}
	if gh.TokenURL != "" {
		endpoints.TokenURL = gh.TokenURL
	}
	if gh.UserURL != "" {
		endpoints.UserURL = gh.UserURL
	}
	if gh.UsersAPIURL != "" {
		endpoints.UsersAPIURL = gh.UsersAPIURL
	}
	return endpoints
}

// resolveSeeds resolves seed usernames to stable identities for every
// allowlisted app that has no completed import marker.
func resolveSeeds(cfg *config.Config, provider auth.Provider, store *policy.Store) (map[string][]*auth.User, error) {
	seeds := make(map[string][]*auth.User)
	for name, appCfg := range cfg.Apps {
		if appCfg.Mode != config.ModeAllowlist {
			continue
		}
		if store.SeedImported(name) {
			slog.Info("seed import already completed", "app", name)
			continue
		}
		users := make([]*auth.User, 0, len(appCfg.SeedUsers))
		for _, login := range appCfg.SeedUsers {
			user, err := provider.ResolveUsername(login)
			if err != nil {
				return nil, fmt.Errorf("app %s: %w", name, err)
			}
			users = append(users, user)
			slog.Info("resolved seed user", "app", name, "username", login, "id", user.ID)
		}
		seeds[name] = users
	}
	return seeds, nil
}
