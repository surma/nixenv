package main

import (
	"fmt"
	"sort"
	"strings"
)

// hostAddrs holds the tailnet addresses of one host. Either may be empty.
type hostAddrs struct {
	V4 string `json:"v4"`
	V6 string `json:"v6"`
}

// config is the JSON document Nix renders from ips.nix.
type config struct {
	Zone    string               `json:"zone"`
	Suffix  string               `json:"suffix"`
	TTL     int                  `json:"ttl"`
	Comment string               `json:"comment"`
	Hosts   map[string]hostAddrs `json:"hosts"`
}

func (c *config) validate() error {
	switch {
	case c.Zone == "":
		return fmt.Errorf("zone is empty")
	case c.Suffix == "":
		return fmt.Errorf("suffix is empty")
	case c.Comment == "":
		return fmt.Errorf("comment is empty; the reconciler refuses to run without an ownership marker")
	case c.TTL < 60:
		return fmt.Errorf("ttl %d is below the Cloudflare minimum of 60", c.TTL)
	case len(c.Hosts) == 0:
		return fmt.Errorf("no hosts declared")
	}
	return nil
}

// record is a Cloudflare DNS record, trimmed to the fields this tool sets.
type record struct {
	ID      string `json:"id,omitempty"`
	Type    string `json:"type"`
	Name    string `json:"name"`
	Content string `json:"content"`
	TTL     int    `json:"ttl"`
	Proxied bool   `json:"proxied"`
	Comment string `json:"comment"`
}

func (r record) key() string { return r.Type + "|" + r.Name }

// desired builds the record set implied by the config. Tailnet addresses sit
// in 100.64.0.0/10 and fd7a::/16, which Cloudflare cannot proxy, so every
// record is DNS-only.
func (c *config) desired() map[string]record {
	out := make(map[string]record, len(c.Hosts)*2)
	for host, addrs := range c.Hosts {
		name := host + "." + c.Suffix
		for _, f := range []struct {
			rtype   string
			content string
		}{
			{"A", addrs.V4},
			{"AAAA", addrs.V6},
		} {
			if f.content == "" {
				continue
			}
			r := record{
				Type:    f.rtype,
				Name:    name,
				Content: f.content,
				TTL:     c.TTL,
				Proxied: false,
				Comment: c.Comment,
			}
			out[r.key()] = r
		}
	}
	return out
}

// owns reports whether a record carries this tool's ownership marker. Only
// owned records are ever updated or deleted.
func (c *config) owns(r record) bool { return r.Comment == c.Comment }

// inScope reports whether a record name sits under the managed suffix.
func (c *config) inScope(r record) bool {
	return strings.HasSuffix(strings.ToLower(r.Name), "."+strings.ToLower(c.Suffix))
}

type verb int

const (
	create verb = iota
	update
	remove
	// skip records that sit under the suffix but belong to someone else.
	adopt
)

func (v verb) String() string {
	switch v {
	case create:
		return "create"
	case update:
		return "update"
	case remove:
		return "delete"
	default:
		return "skip-unowned"
	}
}

// action is one planned change against the Cloudflare zone.
type action struct {
	verb verb
	rec  record
	// prev is the record as Cloudflare currently holds it, for update and
	// delete actions.
	prev record
}

func (a action) String() string {
	switch a.verb {
	case create:
		return fmt.Sprintf("create %s %s -> %s", a.rec.Type, a.rec.Name, a.rec.Content)
	case update:
		return fmt.Sprintf("update %s %s: %s -> %s", a.rec.Type, a.rec.Name, a.prev.Content, a.rec.Content)
	case remove:
		return fmt.Sprintf("delete %s %s (was %s)", a.prev.Type, a.prev.Name, a.prev.Content)
	default:
		return fmt.Sprintf("skip %s %s: not managed by this tool", a.prev.Type, a.prev.Name)
	}
}

// plan diffs the desired records against what Cloudflare currently serves
// under the managed suffix. Records in scope but without the ownership
// marker are reported and left untouched.
func plan(cfg *config, existing []record) []action {
	want := cfg.desired()
	have := make(map[string]record, len(existing))

	var actions []action
	for _, r := range existing {
		if !cfg.inScope(r) {
			continue
		}
		if r.Type != "A" && r.Type != "AAAA" {
			continue
		}
		if _, dup := have[r.key()]; dup {
			// Duplicate name+type. Treat the extra as removable only when we
			// own it, which the delete pass below handles.
			if cfg.owns(r) {
				actions = append(actions, action{verb: remove, prev: r})
			} else {
				actions = append(actions, action{verb: adopt, prev: r})
			}
			continue
		}
		have[r.key()] = r
	}

	keys := make([]string, 0, len(want))
	for k := range want {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	for _, k := range keys {
		w := want[k]
		cur, ok := have[k]
		if !ok {
			actions = append(actions, action{verb: create, rec: w})
			continue
		}
		if !cfg.owns(cur) {
			actions = append(actions, action{verb: adopt, prev: cur})
			continue
		}
		if cur.Content == w.Content && cur.TTL == w.TTL && cur.Proxied == w.Proxied {
			continue
		}
		w.ID = cur.ID
		actions = append(actions, action{verb: update, rec: w, prev: cur})
	}

	stale := make([]string, 0)
	for k := range have {
		if _, ok := want[k]; !ok {
			stale = append(stale, k)
		}
	}
	sort.Strings(stale)
	for _, k := range stale {
		cur := have[k]
		if !cfg.owns(cur) {
			actions = append(actions, action{verb: adopt, prev: cur})
			continue
		}
		actions = append(actions, action{verb: remove, prev: cur})
	}

	return actions
}
