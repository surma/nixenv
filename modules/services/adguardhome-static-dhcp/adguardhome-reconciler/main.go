// Command adguardhome-reconciler converges AdGuardHome's static DHCP
// reservations to a JSON file rendered from ips.nix.
//
// Flow: one health GET, one DHCP-status GET, one delete for every current
// static lease whose MAC appears in the JSON, then one add per JSON lease.
// Static leases with MACs absent from the JSON and all dynamic leases are
// never touched. Any non-2xx response or transport error aborts with a
// non-zero exit code. Progress is logged to stderr, which systemd routes
// to the journal.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultURL = "http://127.0.0.1:8083"

// staticLease is one desired reservation, keyed by MAC in the JSON file.
type staticLease struct {
	IP       string `json:"ip"`
	Hostname string `json:"hostname"`
}

// apiLease mirrors AdGuardHome's REST lease representation.
type apiLease struct {
	Mac      string `json:"mac"`
	IP       string `json:"ip"`
	Hostname string `json:"hostname"`
}

type dhcpStatus struct {
	StaticLeases []apiLease `json:"static_leases"`
}

type client struct {
	baseURL  string
	http     *http.Client
	username string
	password string
}

func (c *client) newRequest(method, path, body string) (*http.Request, error) {
	req, err := http.NewRequest(method, c.baseURL+path, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.username != "" || c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}
	return req, nil
}

func (c *client) get(path string) (*http.Response, error) {
	req, err := c.newRequest(http.MethodGet, path, "")
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		resp.Body.Close()
		return nil, fmt.Errorf("GET %s: status %d", path, resp.StatusCode)
	}
	return resp, nil
}

func (c *client) post(path string, body any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := c.newRequest(http.MethodPost, path, string(payload))
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("POST %s: status %d", path, resp.StatusCode)
	}
	return nil
}

func (c *client) reconcile(leases map[string]staticLease) error {
	health, err := c.get("/control/status")
	if err != nil {
		return fmt.Errorf("health check: %w", err)
	}
	health.Body.Close()

	resp, err := c.get("/control/dhcp/status")
	if err != nil {
		return fmt.Errorf("dhcp status: %w", err)
	}
	defer resp.Body.Close()
	var status dhcpStatus
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		return fmt.Errorf("decode dhcp status: %w", err)
	}
	log.Printf("reconciling static leases: %d configured, %d current", len(leases), len(status.StaticLeases))

	removed, added := 0, 0
	for mac := range leases {
		for _, current := range status.StaticLeases {
			if !strings.EqualFold(current.Mac, mac) {
				continue
			}
			stale := apiLease{Mac: current.Mac, IP: current.IP, Hostname: current.Hostname}
			if err := c.post("/control/dhcp/remove_static_lease", stale); err != nil {
				return fmt.Errorf("remove lease mac=%s ip=%s hostname=%s: %w", stale.Mac, stale.IP, stale.Hostname, err)
			}
			log.Printf("removed static lease: mac=%s ip=%s hostname=%s", stale.Mac, stale.IP, stale.Hostname)
			removed++
			break
		}
	}
	for mac, lease := range leases {
		desired := apiLease{Mac: mac, IP: lease.IP, Hostname: lease.Hostname}
		if err := c.post("/control/dhcp/add_static_lease", desired); err != nil {
			return fmt.Errorf("add lease mac=%s ip=%s hostname=%s: %w", desired.Mac, desired.IP, desired.Hostname, err)
		}
		log.Printf("added static lease: mac=%s ip=%s hostname=%s", desired.Mac, desired.IP, desired.Hostname)
		added++
	}
	log.Printf("reconciled static leases: %d configured, %d removed, %d added", len(leases), removed, added)
	return nil
}

func loadCredentials() (string, string, error) {
	username := strings.TrimSpace(os.Getenv("ADGUARD_USERNAME"))
	if username == "" {
		return "", "", fmt.Errorf("ADGUARD_USERNAME is empty")
	}
	passwordFile := strings.TrimSpace(os.Getenv("ADGUARD_PASSWORD_FILE"))
	if passwordFile == "" {
		return "", "", fmt.Errorf("ADGUARD_PASSWORD_FILE is empty")
	}
	raw, err := os.ReadFile(passwordFile)
	if err != nil {
		return "", "", fmt.Errorf("read ADGUARD_PASSWORD_FILE: %w", err)
	}
	password := strings.TrimSpace(string(raw))
	if password == "" {
		return "", "", fmt.Errorf("ADGUARD_PASSWORD_FILE contains an empty password")
	}
	return username, password, nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: adguardhome-reconciler <static-leases.json>")
		os.Exit(2)
	}
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "read %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
	var leases map[string]staticLease
	if err := json.Unmarshal(raw, &leases); err != nil {
		fmt.Fprintf(os.Stderr, "decode %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
	username, password, err := loadCredentials()
	if err != nil {
		fmt.Fprintf(os.Stderr, "load AdGuardHome credentials: %v\n", err)
		os.Exit(1)
	}
	baseURL := os.Getenv("ADGUARD_URL")
	if baseURL == "" {
		baseURL = defaultURL
	}
	c := &client{
		baseURL:  baseURL,
		http:     &http.Client{Timeout: 10 * time.Second},
		username: username,
		password: password,
	}
	if err := c.reconcile(leases); err != nil {
		fmt.Fprintf(os.Stderr, "adguardhome-reconciler: %v\n", err)
		os.Exit(1)
	}
}
