package main

import (
	"strings"
	"testing"
)

const marker = "managed-by:tailscale-cf-dns"

func testConfig() *config {
	return &config{
		Zone:    "surma.technology",
		Suffix:  "vpn.surma.technology",
		TTL:     300,
		Comment: marker,
		Hosts: map[string]hostAddrs{
			"nexus":   {V4: "100.83.198.90", V6: "fd7a::1"},
			"citadel": {V4: "100.70.63.93"},
		},
	}
}

func owned(rtype, name, content string) record {
	return record{ID: "id-" + name + "-" + rtype, Type: rtype, Name: name, Content: content, TTL: 300, Comment: marker}
}

func verbsFor(actions []action) map[verb][]string {
	out := map[verb][]string{}
	for _, a := range actions {
		name := a.rec.Name
		if name == "" {
			name = a.prev.Name
		}
		out[a.verb] = append(out[a.verb], a.rec.Type+" "+name)
		if a.rec.Type == "" {
			out[a.verb][len(out[a.verb])-1] = a.prev.Type + " " + name
		}
	}
	return out
}

func TestDesiredEmitsARecordAndAAAARecord(t *testing.T) {
	want := testConfig().desired()

	if len(want) != 3 {
		t.Fatalf("want 3 records (2 A + 1 AAAA), got %d: %v", len(want), want)
	}
	a, ok := want["A|nexus.vpn.surma.technology"]
	if !ok {
		t.Fatal("missing A record for nexus")
	}
	if a.Content != "100.83.198.90" || a.TTL != 300 {
		t.Errorf("unexpected A record: %+v", a)
	}
	if a.Proxied {
		t.Error("tailnet records must never be proxied")
	}
	if a.Comment != marker {
		t.Errorf("record is missing the ownership marker: %+v", a)
	}
	if _, ok := want["AAAA|nexus.vpn.surma.technology"]; !ok {
		t.Error("missing AAAA record for nexus")
	}
	if _, ok := want["AAAA|citadel.vpn.surma.technology"]; ok {
		t.Error("citadel has no IPv6 address and must not get an AAAA record")
	}
}

func TestPlanCreatesMissingRecords(t *testing.T) {
	actions := plan(testConfig(), nil)

	if len(actions) != 3 {
		t.Fatalf("want 3 creates, got %d: %v", len(actions), actions)
	}
	for _, a := range actions {
		if a.verb != create {
			t.Errorf("want create, got %v", a)
		}
	}
}

func TestPlanIsNoOpWhenInSync(t *testing.T) {
	existing := []record{
		owned("A", "nexus.vpn.surma.technology", "100.83.198.90"),
		owned("AAAA", "nexus.vpn.surma.technology", "fd7a::1"),
		owned("A", "citadel.vpn.surma.technology", "100.70.63.93"),
	}

	if actions := plan(testConfig(), existing); len(actions) != 0 {
		t.Fatalf("want no actions, got %v", actions)
	}
}

func TestPlanUpdatesChangedContent(t *testing.T) {
	existing := []record{
		owned("A", "nexus.vpn.surma.technology", "100.0.0.1"),
		owned("AAAA", "nexus.vpn.surma.technology", "fd7a::1"),
		owned("A", "citadel.vpn.surma.technology", "100.70.63.93"),
	}

	actions := plan(testConfig(), existing)
	if len(actions) != 1 {
		t.Fatalf("want 1 action, got %v", actions)
	}
	a := actions[0]
	if a.verb != update {
		t.Fatalf("want update, got %v", a)
	}
	if a.prev.ID == "" {
		t.Error("update action lost the record ID")
	}
	if a.rec.Content != "100.83.198.90" {
		t.Errorf("unexpected new content %q", a.rec.Content)
	}
}

func TestPlanDeletesOwnedRecordsForRemovedHosts(t *testing.T) {
	existing := []record{
		owned("A", "nexus.vpn.surma.technology", "100.83.198.90"),
		owned("AAAA", "nexus.vpn.surma.technology", "fd7a::1"),
		owned("A", "citadel.vpn.surma.technology", "100.70.63.93"),
		owned("A", "retired.vpn.surma.technology", "100.1.1.1"),
	}

	actions := plan(testConfig(), existing)
	if len(actions) != 1 {
		t.Fatalf("want 1 action, got %v", actions)
	}
	if actions[0].verb != remove || actions[0].prev.Name != "retired.vpn.surma.technology" {
		t.Fatalf("want delete of retired host, got %v", actions[0])
	}
}

func TestPlanNeverTouchesRecordsItDoesNotOwn(t *testing.T) {
	handMade := record{ID: "manual", Type: "A", Name: "router.vpn.surma.technology", Content: "100.9.9.9", TTL: 1}
	collision := record{ID: "manual2", Type: "A", Name: "nexus.vpn.surma.technology", Content: "1.2.3.4", TTL: 1}

	actions := plan(testConfig(), []record{handMade, collision})

	for _, a := range actions {
		if a.verb == remove {
			t.Errorf("planner tried to delete an unowned record: %v", a)
		}
		if a.verb == update {
			t.Errorf("planner tried to update an unowned record: %v", a)
		}
	}

	var skipped int
	for _, a := range actions {
		if a.verb == adopt {
			skipped++
		}
	}
	if skipped != 2 {
		t.Fatalf("want 2 unowned records reported, got %d: %v", skipped, actions)
	}
}

func TestPlanIgnoresRecordsOutsideTheSuffix(t *testing.T) {
	outside := []record{
		owned("A", "surma.technology", "1.2.3.4"),
		owned("A", "www.surma.technology", "1.2.3.4"),
		owned("A", "nexus.apps.surma.technology", "1.2.3.4"),
		// A record named exactly like the suffix is not a host record.
		owned("A", "vpn.surma.technology", "1.2.3.4"),
	}

	actions := plan(testConfig(), outside)
	for _, a := range actions {
		if a.verb == remove {
			t.Errorf("planner reached outside the managed suffix: %v", a)
		}
	}
	if len(actions) != 3 {
		t.Fatalf("want only the 3 creates, got %v", actions)
	}
}

func TestValidateRejectsMissingOwnershipMarker(t *testing.T) {
	cfg := testConfig()
	cfg.Comment = ""
	if err := cfg.validate(); err == nil {
		t.Fatal("config without an ownership marker must be rejected")
	}
}

func TestValidateRejectsTooLowTTL(t *testing.T) {
	cfg := testConfig()
	cfg.TTL = 30
	err := cfg.validate()
	if err == nil || !strings.Contains(err.Error(), "ttl") {
		t.Fatalf("want a ttl error, got %v", err)
	}
}

func TestDriftLinesReportsMismatchAndUnknownNodes(t *testing.T) {
	cfg := testConfig()
	live := map[string]hostAddrs{
		"nexus":    {V4: "100.83.198.90", V6: "fd7a::1"},
		"citadel":  {V4: "100.70.63.99"},
		"surmbook": {V4: "100.5.5.5"},
	}

	lines := driftLines(cfg, live)
	joined := strings.Join(lines, "\n")

	if !strings.Contains(joined, "citadel") || !strings.Contains(joined, "100.70.63.99") {
		t.Errorf("IPv4 mismatch not reported: %v", lines)
	}
	if !strings.Contains(joined, "surmbook") {
		t.Errorf("unknown tailnet node not reported: %v", lines)
	}
	if strings.Contains(joined, "nexus") {
		t.Errorf("matching host should not be reported: %v", lines)
	}
}

func TestDriftLinesAreCleanWhenInSync(t *testing.T) {
	cfg := testConfig()
	live := map[string]hostAddrs{
		"nexus":   {V4: "100.83.198.90", V6: "fd7a::1"},
		"citadel": {V4: "100.70.63.93"},
	}

	if lines := driftLines(cfg, live); len(lines) != 0 {
		t.Fatalf("want no drift, got %v", lines)
	}
}

func TestLiveAddrsReadsSelfAndPeers(t *testing.T) {
	raw := []byte(`{
      "Self": {"HostName":"nexus","DNSName":"nexus.tail1234.ts.net.","TailscaleIPs":["100.83.198.90","fd7a::1"]},
      "Peer": {
        "nodekey:aaa": {"HostName":"citadel","DNSName":"citadel.tail1234.ts.net.","TailscaleIPs":["100.70.63.93"]}
      }
    }`)

	live, err := liveAddrs(raw)
	if err != nil {
		t.Fatal(err)
	}
	if live["nexus"].V4 != "100.83.198.90" || live["nexus"].V6 != "fd7a::1" {
		t.Errorf("self parsed wrong: %+v", live["nexus"])
	}
	if live["citadel"].V4 != "100.70.63.93" {
		t.Errorf("peer parsed wrong: %+v", live["citadel"])
	}
}
