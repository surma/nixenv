package main

import (
	"strings"
	"testing"
)

// sample mirrors the real ips.nix: hand-aligned columns, a comment header,
// entries with and without a tailscale field, and a nested attribute set.
const sample = `# ips.nix — single source of truth for stable host addresses.
{
  domain = "home.arpa";

  hosts = {
    nexus         = { ip = "10.0.0.2";             tailscale = "100.83.198.90"; };
    citadel       = { mac = "00:e0:4c:03:4b:03";   ip = "10.0.0.3";   tailscale = "100.70.63.93"; };
    wiz-dbb832    = { mac = "98:77:d5:db:b8:32";   ip = "10.0.255.7"; };
    pylon         = { ip = "49.12.5.28";           ipv6 = "2a01:4f8:c17:731::1"; tailscale = "100.64.107.114"; };
  };
}
`

func nodes(entries ...node) map[string]node {
	m := map[string]node{}
	for _, n := range entries {
		m[n.name] = n
	}
	return m
}

func TestUpdateRewritesExistingValueInPlace(t *testing.T) {
	res := update(sample, nodes(node{name: "nexus", v4: "100.99.99.99"}))

	want := `    nexus         = { ip = "10.0.0.2";             tailscale = "100.99.99.99"; };`
	if !strings.Contains(res.source, want) {
		t.Fatalf("rewritten line missing.\nwant: %q\ngot:\n%s", want, res.source)
	}
	if len(res.changes) != 1 {
		t.Fatalf("want 1 change, got %d: %+v", len(res.changes), res.changes)
	}
	if res.changes[0].from != "100.83.198.90" || res.changes[0].to != "100.99.99.99" {
		t.Fatalf("unexpected change: %+v", res.changes[0])
	}
}

func TestUpdateInsertsTailscale6AfterTailscale(t *testing.T) {
	res := update(sample, nodes(node{
		name: "nexus",
		v4:   "100.83.198.90",
		v6:   "fd7a:115c:a1e0::1",
	}))

	want := `    nexus         = { ip = "10.0.0.2";             tailscale = "100.83.198.90"; tailscale6 = "fd7a:115c:a1e0::1"; };`
	if !strings.Contains(res.source, want) {
		t.Fatalf("tailscale6 not inserted after tailscale.\nwant: %q\ngot:\n%s", want, res.source)
	}
}

func TestUpdateInsertsBothFieldsWhenAbsent(t *testing.T) {
	res := update(sample, nodes(node{
		name: "wiz-dbb832",
		v4:   "100.1.2.3",
		v6:   "fd7a::2",
	}))

	want := `    wiz-dbb832    = { mac = "98:77:d5:db:b8:32";   ip = "10.0.255.7"; tailscale = "100.1.2.3"; tailscale6 = "fd7a::2"; };`
	if !strings.Contains(res.source, want) {
		t.Fatalf("fields not appended.\nwant: %q\ngot:\n%s", want, res.source)
	}
}

func TestUpdateLeavesUnrelatedHostsAndCommentsAlone(t *testing.T) {
	res := update(sample, nodes(node{name: "nexus", v4: "100.99.99.99"}))

	for _, keep := range []string{
		`# ips.nix — single source of truth for stable host addresses.`,
		`  domain = "home.arpa";`,
		`    citadel       = { mac = "00:e0:4c:03:4b:03";   ip = "10.0.0.3";   tailscale = "100.70.63.93"; };`,
		`    wiz-dbb832    = { mac = "98:77:d5:db:b8:32";   ip = "10.0.255.7"; };`,
		`    pylon         = { ip = "49.12.5.28";           ipv6 = "2a01:4f8:c17:731::1"; tailscale = "100.64.107.114"; };`,
	} {
		if !strings.Contains(res.source, keep) {
			t.Errorf("line was modified but should not have been: %q", keep)
		}
	}
}

func TestUpdateIsIdempotent(t *testing.T) {
	ns := nodes(node{name: "nexus", v4: "100.83.198.90", v6: "fd7a::1"})

	first := update(sample, ns)
	if len(first.changes) == 0 {
		t.Fatal("first pass made no changes")
	}
	second := update(first.source, ns)
	if len(second.changes) != 0 {
		t.Fatalf("second pass was not a no-op: %+v", second.changes)
	}
	if second.source != first.source {
		t.Fatal("second pass rewrote the file")
	}
}

func TestUpdateReportsTailnetNodesWithoutEntry(t *testing.T) {
	res := update(sample, nodes(
		node{name: "nexus", v4: "100.83.198.90"},
		node{name: "surmbook", v4: "100.5.5.5"},
	))

	if len(res.unmatched) != 1 || res.unmatched[0] != "surmbook" {
		t.Fatalf("want unmatched=[surmbook], got %v", res.unmatched)
	}
}

func TestUpdateReportsDeclaredHostsMissingFromTailnet(t *testing.T) {
	res := update(sample, nodes(node{name: "nexus", v4: "100.83.198.90"}))

	want := map[string]bool{"citadel": true, "pylon": true}
	if len(res.offTailnet) != len(want) {
		t.Fatalf("want %d off-tailnet hosts, got %v", len(want), res.offTailnet)
	}
	for _, h := range res.offTailnet {
		if !want[h] {
			t.Errorf("unexpected off-tailnet host %q", h)
		}
	}
	// wiz-dbb832 has no tailscale field, so it is not VPN-relevant noise.
	for _, h := range res.offTailnet {
		if h == "wiz-dbb832" {
			t.Error("host without a tailscale field should not be reported")
		}
	}
}

func TestUpdateIgnoresAttributesOutsideHostsBlock(t *testing.T) {
	src := `{
  other = {
    nexus = { tailscale = "1.1.1.1"; };
  };

  hosts = {
    nexus = { ip = "10.0.0.2"; tailscale = "100.83.198.90"; };
  };
}
`
	res := update(src, nodes(node{name: "nexus", v4: "100.99.99.99"}))

	if !strings.Contains(res.source, `nexus = { tailscale = "1.1.1.1"; };`) {
		t.Error("entry outside the hosts block was modified")
	}
	if !strings.Contains(res.source, `nexus = { ip = "10.0.0.2"; tailscale = "100.99.99.99"; };`) {
		t.Error("entry inside the hosts block was not updated")
	}
}

func TestShortNamePrefersMagicDNSLabel(t *testing.T) {
	for _, tc := range []struct {
		peer *statusPeer
		want string
	}{
		{&statusPeer{DNSName: "nexus.tail1234.ts.net.", HostName: "Nexus-Box"}, "nexus"},
		{&statusPeer{DNSName: "", HostName: "Pixel-8a"}, "pixel-8a"},
		{&statusPeer{DNSName: "citadel.tail1234.ts.net", HostName: ""}, "citadel"},
	} {
		if got := tc.peer.shortName(); got != tc.want {
			t.Errorf("shortName(%+v) = %q, want %q", tc.peer, got, tc.want)
		}
	}
}

func TestSplitSeparatesAddressFamilies(t *testing.T) {
	p := &statusPeer{TailscaleIPs: []string{"100.83.198.90", "fd7a:115c:a1e0:ab12::1"}}
	v4, v6 := p.split()
	if v4 != "100.83.198.90" {
		t.Errorf("v4 = %q", v4)
	}
	if v6 != "fd7a:115c:a1e0:ab12::1" {
		t.Errorf("v6 = %q", v6)
	}
}
