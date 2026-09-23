// Command tailscale-cf-dns converges Cloudflare DNS records for the tailnet
// to a JSON file rendered from ips.nix.
//
// For every declared host it publishes `<host>.<suffix>` as an A record for
// the Tailscale IPv4 address and an AAAA record for the IPv6 address. Both
// are DNS-only: Cloudflare cannot proxy 100.64.0.0/10 or fd7a::/16.
//
// Ownership is tracked with the record comment. The reconciler creates,
// updates, and deletes only records carrying its marker. A record under the
// managed suffix without that marker is reported and left alone, so a
// hand-made entry is never clobbered.
//
// The tool also compares the declared addresses against the live tailnet
// when the tailscale CLI is reachable. Drift is logged and never acted on:
// ips.nix stays the source of truth, and `tailscale-ips-update` is the tool
// that changes it.
//
// Exit codes: 0 on success, 1 on error. Progress goes to stderr, which
// systemd routes to the journal.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const apiBase = "https://api.cloudflare.com/client/v4"

// envelope is the wrapper Cloudflare puts around every response.
type envelope struct {
	Success bool            `json:"success"`
	Errors  []apiError      `json:"errors"`
	Result  json.RawMessage `json:"result"`
	Info    struct {
		Page       int `json:"page"`
		TotalPages int `json:"total_pages"`
	} `json:"result_info"`
}

type apiError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e apiError) Error() string { return fmt.Sprintf("cloudflare %d: %s", e.Code, e.Message) }

type client struct {
	token string
	http  *http.Client
}

func (c *client) do(method, path string, body any) (*envelope, error) {
	var payload io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		payload = bytes.NewReader(raw)
	}

	req, err := http.NewRequest(method, apiBase+path, payload)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var env envelope
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return nil, fmt.Errorf("%s %s: decode response (status %d): %w", method, path, resp.StatusCode, err)
	}
	if !env.Success {
		if len(env.Errors) > 0 {
			return nil, fmt.Errorf("%s %s: %w", method, path, env.Errors[0])
		}
		return nil, fmt.Errorf("%s %s: status %d", method, path, resp.StatusCode)
	}
	return &env, nil
}

// zoneID resolves a zone name to its Cloudflare identifier.
func (c *client) zoneID(name string) (string, error) {
	env, err := c.do(http.MethodGet, "/zones?name="+url.QueryEscape(name), nil)
	if err != nil {
		return "", err
	}
	var zones []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(env.Result, &zones); err != nil {
		return "", err
	}
	for _, z := range zones {
		if strings.EqualFold(z.Name, name) {
			return z.ID, nil
		}
	}
	return "", fmt.Errorf("zone %q not found; check the API token scope", name)
}

// listRecords fetches every A and AAAA record in the zone.
func (c *client) listRecords(zoneID string) ([]record, error) {
	var out []record
	for _, rtype := range []string{"A", "AAAA"} {
		for page := 1; ; page++ {
			path := fmt.Sprintf("/zones/%s/dns_records?type=%s&per_page=100&page=%d", zoneID, rtype, page)
			env, err := c.do(http.MethodGet, path, nil)
			if err != nil {
				return nil, err
			}
			var batch []record
			if err := json.Unmarshal(env.Result, &batch); err != nil {
				return nil, err
			}
			out = append(out, batch...)
			if env.Info.TotalPages <= page {
				break
			}
		}
	}
	return out, nil
}

func (c *client) apply(zoneID string, a action) error {
	switch a.verb {
	case create:
		_, err := c.do(http.MethodPost, "/zones/"+zoneID+"/dns_records", a.rec)
		return err
	case update:
		body := a.rec
		body.ID = ""
		_, err := c.do(http.MethodPut, "/zones/"+zoneID+"/dns_records/"+a.prev.ID, body)
		return err
	case remove:
		_, err := c.do(http.MethodDelete, "/zones/"+zoneID+"/dns_records/"+a.prev.ID, nil)
		return err
	}
	return nil
}

func loadToken() (string, error) {
	path := strings.TrimSpace(os.Getenv("CLOUDFLARE_API_TOKEN_FILE"))
	if path == "" {
		return "", fmt.Errorf("CLOUDFLARE_API_TOKEN_FILE is empty")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read CLOUDFLARE_API_TOKEN_FILE: %w", err)
	}
	token := strings.TrimSpace(string(raw))
	if token == "" {
		return "", fmt.Errorf("%s contains an empty token", path)
	}
	return token, nil
}

func run() error {
	dryRun := flag.Bool("dry-run", false, "print the plan and change nothing")
	flag.Parse()

	if flag.NArg() != 1 {
		return fmt.Errorf("usage: tailscale-cf-dns [-dry-run] <config.json>")
	}

	raw, err := os.ReadFile(flag.Arg(0))
	if err != nil {
		return fmt.Errorf("read %s: %w", flag.Arg(0), err)
	}
	var cfg config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return fmt.Errorf("decode %s: %w", flag.Arg(0), err)
	}
	if err := cfg.validate(); err != nil {
		return fmt.Errorf("invalid config %s: %w", flag.Arg(0), err)
	}

	reportDrift(&cfg)

	token, err := loadToken()
	if err != nil {
		return err
	}

	c := &client{token: token, http: &http.Client{Timeout: 30 * time.Second}}

	zoneID, err := c.zoneID(cfg.Zone)
	if err != nil {
		return err
	}

	existing, err := c.listRecords(zoneID)
	if err != nil {
		return fmt.Errorf("list records: %w", err)
	}

	actions := plan(&cfg, existing)
	if len(actions) == 0 {
		log.Printf("%s is up to date: %d host(s), nothing to do", cfg.Suffix, len(cfg.Hosts))
		return nil
	}

	applied := map[verb]int{}
	for _, a := range actions {
		if a.verb == adopt {
			log.Printf("SKIP %s", a)
			applied[adopt]++
			continue
		}
		if *dryRun {
			log.Printf("DRY-RUN %s", a)
			applied[a.verb]++
			continue
		}
		if err := c.apply(zoneID, a); err != nil {
			return fmt.Errorf("%s: %w", a, err)
		}
		log.Printf("%s", a)
		applied[a.verb]++
	}

	log.Printf("reconciled %s: %d created, %d updated, %d deleted, %d left unmanaged",
		cfg.Suffix, applied[create], applied[update], applied[remove], applied[adopt])
	return nil
}

func main() {
	log.SetFlags(0)
	log.SetPrefix("tailscale-cf-dns: ")
	if err := run(); err != nil {
		log.Printf("error: %v", err)
		os.Exit(1)
	}
}
