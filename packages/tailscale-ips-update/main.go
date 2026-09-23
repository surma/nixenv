// Command tailscale-ips-update refreshes the `tailscale` and `tailscale6`
// fields in ips.nix from the live tailnet.
//
// The tool edits ips.nix in place and touches nothing else. It rewrites the
// value inside an existing field, or inserts the field into an existing host
// entry. Comments, column alignment, and every other field stay byte for
// byte identical. Only entries inside the `hosts = { ... }` block are
// considered.
//
// Host entries are matched by their ips.nix attribute name against the
// MagicDNS short name of each tailnet node. A tailnet node with no matching
// entry is reported but never added: ips.nix keys are DHCP hostnames, and a
// new entry needs a `mac` and an `ip` that this tool cannot know. Adding a
// host stays a deliberate edit.
//
// Exit codes: 0 on success, 1 on error, and in -check mode 1 when ips.nix is
// out of date.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
)

// node is one tailnet machine reduced to the two addresses ips.nix records.
type node struct {
	name string
	v4   string
	v6   string
}

// statusPeer mirrors the subset of `tailscale status --json` this tool reads.
type statusPeer struct {
	HostName     string   `json:"HostName"`
	DNSName      string   `json:"DNSName"`
	TailscaleIPs []string `json:"TailscaleIPs"`
}

type status struct {
	Self *statusPeer            `json:"Self"`
	Peer map[string]*statusPeer `json:"Peer"`
}

// shortName reduces a MagicDNS name to its first label, which is the
// sanitized machine name Tailscale itself uses. HostName is the fallback for
// nodes with MagicDNS disabled.
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

// split sorts the node addresses into the first IPv4 and the first IPv6.
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

// readStatus loads tailnet state. An empty path runs the tailscale CLI.
func readStatus(path string) (map[string]node, error) {
	var raw []byte
	var err error
	if path == "" {
		raw, err = exec.Command("tailscale", "status", "--json").Output()
		if err != nil {
			return nil, fmt.Errorf("run tailscale status --json: %w", err)
		}
	} else {
		raw, err = os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", path, err)
		}
	}

	var s status
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, fmt.Errorf("decode tailscale status: %w", err)
	}

	peers := make([]*statusPeer, 0, len(s.Peer)+1)
	if s.Self != nil {
		peers = append(peers, s.Self)
	}
	for _, p := range s.Peer {
		peers = append(peers, p)
	}

	nodes := make(map[string]node, len(peers))
	for _, p := range peers {
		name := p.shortName()
		if name == "" {
			continue
		}
		v4, v6 := p.split()
		if v4 == "" && v6 == "" {
			continue
		}
		nodes[name] = node{name: name, v4: v4, v6: v6}
	}
	if len(nodes) == 0 {
		return nil, fmt.Errorf("tailscale status reported no nodes")
	}
	return nodes, nil
}

var (
	hostsOpenRe = regexp.MustCompile(`^\s*hosts\s*=\s*\{\s*$`)
	entryRe     = regexp.MustCompile(`^(\s+)([A-Za-z0-9_-]+)(\s*)=\s*\{(.*)\};(\s*)$`)
)

// fieldRe matches `name = "value"` and captures the value separately so a
// rewrite preserves the spacing the author chose around the equals sign.
func fieldRe(name string) *regexp.Regexp {
	return regexp.MustCompile(`\b` + name + `\s*=\s*"([^"]*)"`)
}

// setField rewrites an existing field value in a host entry body. It reports
// whether the body changed and whether the field was present at all.
func setField(body, name, value string) (out string, changed, present bool) {
	loc := fieldRe(name).FindStringSubmatchIndex(body)
	if loc == nil {
		return body, false, false
	}
	if body[loc[2]:loc[3]] == value {
		return body, false, true
	}
	return body[:loc[2]] + value + body[loc[3]:], true, true
}

// insertField adds `name = "value";` to a host entry body. It lands directly
// after the field named `after` when that field exists, and otherwise at the
// end of the body.
func insertField(body, name, value, after string) string {
	field := name + ` = "` + value + `";`

	if after != "" {
		if loc := fieldRe(after).FindStringIndex(body); loc != nil {
			end := loc[1]
			// Step over the semicolon that terminates the anchor field.
			if end < len(body) && body[end] == ';' {
				end++
			}
			return body[:end] + " " + field + body[end:]
		}
	}

	trimmed := strings.TrimRight(body, " ")
	trailing := body[len(trimmed):]
	if trailing == "" {
		trailing = " "
	}
	if trimmed == "" {
		return " " + field + trailing
	}
	return trimmed + " " + field + trailing
}

// change records one field edit for the run summary.
type change struct {
	host  string
	field string
	from  string
	to    string
}

// result carries everything a caller needs to report on a run.
type result struct {
	source  string
	changes []change
	// unmatched lists tailnet nodes with no ips.nix entry.
	unmatched []string
	// offTailnet lists ips.nix hosts that carry a `tailscale` field but are
	// absent from the tailnet.
	offTailnet []string
}

// update applies tailnet addresses to the ips.nix source text.
func update(src string, nodes map[string]node) result {
	lines := strings.Split(src, "\n")
	res := result{}
	seen := map[string]bool{}

	depth := 0
	inHosts := false
	for i, line := range lines {
		if !inHosts {
			if hostsOpenRe.MatchString(line) {
				inHosts = true
				depth = 1
			}
			continue
		}

		m := entryRe.FindStringSubmatch(line)
		if m == nil {
			depth += strings.Count(line, "{") - strings.Count(line, "}")
			if depth <= 0 {
				inHosts = false
			}
			continue
		}

		host := m[2]
		body := m[4]
		n, ok := nodes[strings.ToLower(host)]
		if !ok {
			if fieldRe("tailscale").MatchString(body) {
				res.offTailnet = append(res.offTailnet, host)
			}
			continue
		}
		seen[strings.ToLower(host)] = true

		for _, f := range []struct{ name, value, after string }{
			{"tailscale", n.v4, ""},
			{"tailscale6", n.v6, "tailscale"},
		} {
			if f.value == "" {
				continue
			}
			before := fieldRe(f.name).FindStringSubmatch(body)
			updated, changed, present := setField(body, f.name, f.value)
			switch {
			case !present:
				body = insertField(body, f.name, f.value, f.after)
				res.changes = append(res.changes, change{host: host, field: f.name, from: "", to: f.value})
			case changed:
				body = updated
				res.changes = append(res.changes, change{host: host, field: f.name, from: before[1], to: f.value})
			}
		}

		lines[i] = m[1] + m[2] + m[3] + "= {" + body + "};" + m[5]
	}

	for name := range nodes {
		if !seen[name] {
			res.unmatched = append(res.unmatched, name)
		}
	}
	sort.Strings(res.unmatched)
	sort.Strings(res.offTailnet)
	res.source = strings.Join(lines, "\n")
	return res
}

func main() {
	var (
		ipsFile    = flag.String("ips-file", "ips.nix", "path to ips.nix")
		statusJSON = flag.String("status-json", "", "read tailnet state from this file instead of running the tailscale CLI")
		check      = flag.Bool("check", false, "report drift and exit 1 without writing")
	)
	flag.Parse()

	nodes, err := readStatus(*statusJSON)
	if err != nil {
		fmt.Fprintf(os.Stderr, "tailscale-ips-update: %v\n", err)
		os.Exit(1)
	}

	raw, err := os.ReadFile(*ipsFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "tailscale-ips-update: read %s: %v\n", *ipsFile, err)
		os.Exit(1)
	}

	res := update(string(raw), nodes)

	for _, c := range res.changes {
		if c.from == "" {
			fmt.Printf("%s: %s set to %s\n", c.host, c.field, c.to)
			continue
		}
		fmt.Printf("%s: %s %s -> %s\n", c.host, c.field, c.from, c.to)
	}
	for _, name := range res.unmatched {
		fmt.Printf("note: tailnet node %q has no ips.nix entry; add it by hand if you want a DNS record\n", name)
	}
	for _, host := range res.offTailnet {
		fmt.Printf("note: ips.nix host %q declares a tailscale address but is not in the tailnet right now\n", host)
	}

	if len(res.changes) == 0 {
		fmt.Printf("%s is up to date\n", *ipsFile)
		return
	}

	if *check {
		fmt.Fprintf(os.Stderr, "tailscale-ips-update: %s is out of date (%d change(s))\n", *ipsFile, len(res.changes))
		os.Exit(1)
	}

	if err := os.WriteFile(*ipsFile, []byte(res.source), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "tailscale-ips-update: write %s: %v\n", *ipsFile, err)
		os.Exit(1)
	}
	fmt.Printf("updated %s (%d change(s))\n", *ipsFile, len(res.changes))
}
