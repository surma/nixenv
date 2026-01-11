package auth

import (
	"context"
	"encoding/json"
	"fmt"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/github"
)

// GitHubProvider implements OAuth authentication with GitHub
type GitHubProvider struct {
	config *oauth2.Config
}

// NewGitHubProvider creates a new GitHub OAuth provider
func NewGitHubProvider(clientID, clientSecret, redirectURL string) *GitHubProvider {
	return &GitHubProvider{
		config: &oauth2.Config{
			ClientID:     clientID,
			ClientSecret: clientSecret,
			RedirectURL:  redirectURL,
			Scopes:       []string{"read:user", "user:email"},
			Endpoint:     github.Endpoint,
		},
	}
}

// Name returns the provider name
func (p *GitHubProvider) Name() string {
	return "github"
}

// AuthURL returns the OAuth authorization URL
func (p *GitHubProvider) AuthURL(state string) string {
	return p.config.AuthCodeURL(state, oauth2.AccessTypeOnline)
}

// Exchange exchanges an authorization code for user information
func (p *GitHubProvider) Exchange(code string) (*User, error) {
	ctx := context.Background()

	// Exchange code for token
	token, err := p.config.Exchange(ctx, code)
	if err != nil {
		return nil, fmt.Errorf("failed to exchange code: %w", err)
	}

	// Get user info from GitHub API
	client := p.config.Client(ctx, token)
	resp, err := client.Get("https://api.github.com/user")
	if err != nil {
		return nil, fmt.Errorf("failed to get user info: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("GitHub API returned status %d", resp.StatusCode)
	}

	var githubUser struct {
		ID        int    `json:"id"`
		Login     string `json:"login"`
		Email     string `json:"email"`
		AvatarURL string `json:"avatar_url"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&githubUser); err != nil {
		return nil, fmt.Errorf("failed to decode user info: %w", err)
	}

	return &User{
		ID:       fmt.Sprintf("%d", githubUser.ID),
		Username: githubUser.Login,
		Email:    githubUser.Email,
		Avatar:   githubUser.AvatarURL,
	}, nil
}
