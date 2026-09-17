// Command adguardhome-reconciler converges AdGuardHome's static DHCP
// reservations to a JSON file rendered from ips.nix.
//
// Flow: one health GET, one DHCP-status GET, one delete for every current
// static lease whose MAC appears in the JSON, then one add per JSON lease.
// Static leases with MACs absent from the JSON and all dynamic leases are
// never touched. Any non-2xx response or transport error aborts with a
// non-zero exit code.
package main

import (
	"encoding/json"
	"fmt"
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
	baseURL string
	http    *http.Client
}

func (c *client) get(path string) (*http.Response, error) {
	resp, err := c.http.Get(c.baseURL + path)
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
	resp, err := c.http.Post(c.baseURL+path, "application/json", strings.NewReader(string(payload)))
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

	for mac := range leases {
		for _, current := range status.StaticLeases {
			if !strings.EqualFold(current.Mac, mac) {
				continue
			}
			stale := apiLease{Mac: current.Mac, IP: current.IP, Hostname: current.Hostname}
			if err := c.post("/control/dhcp/remove_static_lease", stale); err != nil {
				return fmt.Errorf("remove lease %s: %w", mac, err)
			}
			break
		}
	}
	for mac, lease := range leases {
		desired := apiLease{Mac: mac, IP: lease.IP, Hostname: lease.Hostname}
		if err := c.post("/control/dhcp/add_static_lease", desired); err != nil {
			return fmt.Errorf("add lease %s: %w", mac, err)
		}
	}
	return nil
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
	baseURL := os.Getenv("ADGUARD_URL")
	if baseURL == "" {
		baseURL = defaultURL
	}
	c := &client{
		baseURL: baseURL,
		http:    &http.Client{Timeout: 10 * time.Second},
	}
	if err := c.reconcile(leases); err != nil {
		fmt.Fprintf(os.Stderr, "adguardhome-reconciler: %v\n", err)
		os.Exit(1)
	}
}
