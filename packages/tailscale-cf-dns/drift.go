package main

import (
	"encoding/json"
	"log"
	"os/exec"
	"sort"
	"strings"
)

// statusPeer mirrors the subset of `tailscale status --json` the drift check
// reads.
type statusPeer struct {
	HostName     string   `json:"HostName"`
	DNSName      string   `json:"DNSName"`
	TailscaleIPs []string `json:"TailscaleIPs"`
}

type tailscaleStatus struct {
	Self *statusPeer            `json:"Self"`
	Peer map[string]*statusPeer `json:"Peer"`
}

func (p *statusPeer) shortName() string {
	name := strings.TrimSuffix(p.DNSName, ".")
	if name == "" {
		name = p.HostName
	}
	if i := strings.Index(name, "."); i >= 0 {
		name = name[:i]
	}
	return strings.ToLower(name)
}

func (p *statusPeer) split() (v4, v6 string) {
	for _, ip := range p.TailscaleIPs {
		if strings.Contains(ip, ":") {
			if v6 == "" {
				v6 = ip
			}
			continue
		}
		if v4 == "" {
			v4 = ip
		}
	}
	return v4, v6
}

// liveAddrs reduces a status document to host -> addresses.
func liveAddrs(raw []byte) (map[string]hostAddrs, error) {
	var s tailscaleStatus
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, err
	}
	peers := make([]*statusPeer, 0, len(s.Peer)+1)
	if s.Self != nil {
		peers = append(peers, s.Self)
	}
	for _, p := range s.Peer {
		peers = append(peers, p)
	}
	out := make(map[string]hostAddrs, len(peers))
	for _, p := range peers {
		name := p.shortName()
		if name == "" {
			continue
		}
		v4, v6 := p.split()
		out[name] = hostAddrs{V4: v4, V6: v6}
	}
	return out, nil
}

// driftLines compares declared addresses against the live tailnet and
// returns one human-readable line per discrepancy.
func driftLines(cfg *config, live map[string]hostAddrs) []string {
	var lines []string

	declared := make([]string, 0, len(cfg.Hosts))
	for host := range cfg.Hosts {
		declared = append(declared, host)
	}
	sort.Strings(declared)

	for _, host := range declared {
		want := cfg.Hosts[host]
		got, ok := live[strings.ToLower(host)]
		if !ok {
			lines = append(lines, "declared host "+host+" is not in the tailnet right now")
			continue
		}
		if got.V4 != "" && want.V4 != "" && got.V4 != want.V4 {
			lines = append(lines, "host "+host+" has tailnet IPv4 "+got.V4+" but ips.nix declares "+want.V4)
		}
		if got.V6 != "" && want.V6 == "" {
			lines = append(lines, "host "+host+" has tailnet IPv6 "+got.V6+" but ips.nix declares none")
		}
		if got.V6 != "" && want.V6 != "" && got.V6 != want.V6 {
			lines = append(lines, "host "+host+" has tailnet IPv6 "+got.V6+" but ips.nix declares "+want.V6)
		}
	}

	extra := make([]string, 0)
	for host := range live {
		if _, ok := cfg.Hosts[host]; !ok {
			extra = append(extra, host)
		}
	}
	sort.Strings(extra)
	for _, host := range extra {
		lines = append(lines, "tailnet node "+host+" has no ips.nix entry and gets no DNS record")
	}

	return lines
}

// reportDrift logs differences between ips.nix and the live tailnet. It
// never changes anything and never fails the run: a missing or unreachable
// tailscale CLI is a soft condition, because the reconciler is declarative
// by design.
func reportDrift(cfg *config) {
	raw, err := exec.Command("tailscale", "status", "--json").Output()
	if err != nil {
		log.Printf("drift check skipped: %v", err)
		return
	}
	live, err := liveAddrs(raw)
	if err != nil {
		log.Printf("drift check skipped: decode tailscale status: %v", err)
		return
	}
	lines := driftLines(cfg, live)
	if len(lines) == 0 {
		log.Printf("drift check: ips.nix matches the tailnet")
		return
	}
	for _, l := range lines {
		log.Printf("DRIFT %s", l)
	}
	log.Printf("drift check: %d discrepancy(ies); run `nix run .#tailscale-ips-update` and commit to resolve", len(lines))
}
