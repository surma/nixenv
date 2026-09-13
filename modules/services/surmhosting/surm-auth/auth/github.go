package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/github"
)

// GitHubEndpoints holds the HTTP endpoints used by GitHubProvider.
// Tests inject httptest URLs; production uses the GitHub defaults.
type GitHubEndpoints struct {
	// AuthURL is the authorization endpoint.
	AuthURL string
	// TokenURL is the token exchange endpoint.
	TokenURL string
	// UserURL returns the authenticated user.
	UserURL string
	// UsersAPIURL is the user lookup base; ResolveUsername appends
	// "/<login>" to it.
	UsersAPIURL string
}

// DefaultGitHubEndpoints returns the public GitHub endpoints.
func DefaultGitHubEndpoints() GitHubEndpoints {
	return GitHubEndpoints{
		AuthURL:     github.Endpoint.AuthURL,
		TokenURL:    github.Endpoint.TokenURL,
		UserURL:     "https://api.github.com/user",
		UsersAPIURL: "https://api.github.com/users",
	}
}

// GitHubProvider implements Provider for GitHub.
type GitHubProvider struct {
	config      *oauth2.Config
	userURL     string
	usersAPIURL string
	client      *http.Client
}

// NewGitHubProvider creates a new GitHub OAuth provider. The endpoints
// and HTTP client are injectable so tests never contact GitHub. A nil
// client selects http.DefaultClient.
func NewGitHubProvider(clientID, clientSecret, redirectURL string, endpoints GitHubEndpoints, client *http.Client) *GitHubProvider {
	if client == nil {
		client = http.DefaultClient
	}
	return &GitHubProvider{
		config: &oauth2.Config{
			ClientID:     clientID,
			ClientSecret: clientSecret,
			RedirectURL:  redirectURL,
			Scopes:       []string{"read:user"},
			Endpoint: oauth2.Endpoint{
				AuthURL:  endpoints.AuthURL,
				TokenURL: endpoints.TokenURL,
			},
		},
		userURL:     endpoints.UserURL,
		usersAPIURL: endpoints.UsersAPIURL,
		client:      client,
	}
}

// Name returns the provider name.
func (p *GitHubProvider) Name() string {
	return "github"
}

// AuthURL returns the OAuth authorization URL.
func (p *GitHubProvider) AuthURL(state string) string {
	return p.config.AuthCodeURL(state, oauth2.AccessTypeOnline)
}

// Exchange exchanges an authorization code for user information.
func (p *GitHubProvider) Exchange(code string) (*User, error) {
	ctx := context.WithValue(context.Background(), oauth2.HTTPClient, p.client)

	token, err := p.config.Exchange(ctx, code)
	if err != nil {
		return nil, fmt.Errorf("failed to exchange code: %w", err)
	}

	return p.fetchUser(p.config.Client(ctx, token), p.userURL)
}

// ResolveUsername resolves a username to the canonical user including
// the stable numeric ID. Unresolved users return an error and never
// produce a grant.
func (p *GitHubProvider) ResolveUsername(login string) (*User, error) {
	login = strings.TrimSpace(login)
	if login == "" {
		return nil, fmt.Errorf("username must not be empty")
	}
	lookupURL := strings.TrimSuffix(p.usersAPIURL, "/") + "/" + url.PathEscape(login)
	return p.fetchUser(p.client, lookupURL)
}

func (p *GitHubProvider) fetchUser(client *http.Client, userURL string) (*User, error) {
	resp, err := client.Get(userURL)
	if err != nil {
		return nil, fmt.Errorf("failed to get user info: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("user endpoint %s returned status %d", userURL, resp.StatusCode)
	}

	var githubUser struct {
		ID        json.Number `json:"id"`
		Login     string      `json:"login"`
		Email     string      `json:"email"`
		AvatarURL string      `json:"avatar_url"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&githubUser); err != nil {
		return nil, fmt.Errorf("failed to decode user info: %w", err)
	}

	id := strings.TrimSpace(githubUser.ID.String())
	if id == "" || id == "null" {
		return nil, fmt.Errorf("user endpoint %s returned no numeric ID", userURL)
	}

	return &User{
		Provider: p.Name(),
		ID:       id,
		Username: githubUser.Login,
		Email:    githubUser.Email,
		Avatar:   githubUser.AvatarURL,
	}, nil
}
