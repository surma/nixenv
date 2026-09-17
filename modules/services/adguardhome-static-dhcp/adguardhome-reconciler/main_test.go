package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type recordedCall struct {
	method string
	path   string
	body   string
}

// newTestClient starts an httptest server that records every request and
// serves the given handlers by path. It returns the client under test and
// the call log.
func newTestClient(t *testing.T, statusBody string, postHandler http.HandlerFunc) (*client, *[]recordedCall) {
	t.Helper()
	var calls []recordedCall
	mux := http.NewServeMux()
	mux.HandleFunc("/control/status", func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, recordedCall{r.Method, r.URL.Path, ""})
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/control/dhcp/status", func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, recordedCall{r.Method, r.URL.Path, ""})
		w.Write([]byte(statusBody))
	})
	if postHandler != nil {
		mux.HandleFunc("/control/dhcp/remove_static_lease", func(w http.ResponseWriter, r *http.Request) {
			body, _ := io.ReadAll(r.Body)
			calls = append(calls, recordedCall{r.Method, r.URL.Path, string(body)})
			postHandler(w, r)
		})
		mux.HandleFunc("/control/dhcp/add_static_lease", func(w http.ResponseWriter, r *http.Request) {
			body, _ := io.ReadAll(r.Body)
			calls = append(calls, recordedCall{r.Method, r.URL.Path, string(body)})
			postHandler(w, r)
		})
	}
	server := httptest.NewServer(mux)
	t.Cleanup(server.Close)
	return &client{baseURL: server.URL, http: server.Client()}, &calls
}

const statusBodyWithDrift = `{
  "static_leases": [
    {"mac": "00:e0:4c:03:4b:03", "ip": "10.0.0.3", "hostname": "citadel"},
    {"mac": "36:8f:cc:d6:6f:ff", "ip": "10.9.9.9", "hostname": "dragoon"},
    {"mac": "de:ad:be:ef:00:01", "ip": "10.0.255.50", "hostname": "extra-device"}
  ],
  "leases": [
    {"mac": "aa:bb:cc:00:00:01", "ip": "10.0.255.1", "hostname": "p100"}
  ]
}`

func TestEndpointOrderAndMerge(t *testing.T) {
	leases := map[string]staticLease{
		"00:e0:4c:03:4b:03": {IP: "10.0.0.3", Hostname: "citadel"},
		"36:8f:cc:d6:6f:ff": {IP: "10.0.1.1", Hostname: "dragoon"},
	}
	c, calls := newTestClient(t, statusBodyWithDrift, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	if err := c.reconcile(leases); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	// Order: health GET, DHCP-status GET, removes, adds.
	if len(*calls) != 6 {
		t.Fatalf("want 6 calls, got %d: %+v", len(*calls), *calls)
	}
	wantOrder := []string{
		"/control/status",
		"/control/dhcp/status",
		"/control/dhcp/remove_static_lease",
		"/control/dhcp/remove_static_lease",
		"/control/dhcp/add_static_lease",
		"/control/dhcp/add_static_lease",
	}
	for i, want := range wantOrder {
		if (*calls)[i].path != want {
			t.Errorf("call %d: got %s, want %s", i, (*calls)[i].path, want)
		}
	}

	// Merge behavior: every registry-MAC lease is removed (with the values
	// as currently stored) and re-added with the JSON values. The product
	// iterates a Go map, so within the remove and add groups the order is
	// random: compare the bodies as MAC-keyed sets, not positionally.
	type apiLease struct {
		Mac      string `json:"mac"`
		IP       string `json:"ip"`
		Hostname string `json:"hostname"`
	}
	wantRemoves := map[string]apiLease{
		"00:e0:4c:03:4b:03": {Mac: "00:e0:4c:03:4b:03", IP: "10.0.0.3", Hostname: "citadel"},
		"36:8f:cc:d6:6f:ff": {Mac: "36:8f:cc:d6:6f:ff", IP: "10.9.9.9", Hostname: "dragoon"},
	}
	wantAdds := map[string]apiLease{
		"00:e0:4c:03:4b:03": {Mac: "00:e0:4c:03:4b:03", IP: "10.0.0.3", Hostname: "citadel"},
		"36:8f:cc:d6:6f:ff": {Mac: "36:8f:cc:d6:6f:ff", IP: "10.0.1.1", Hostname: "dragoon"},
	}
	gotRemoves := map[string]apiLease{}
	gotAdds := map[string]apiLease{}
	for _, call := range (*calls)[2:] {
		var got apiLease
		if err := json.Unmarshal([]byte(call.body), &got); err != nil {
			t.Fatalf("decode %s body: %v", call.path, err)
		}
		switch call.path {
		case "/control/dhcp/remove_static_lease":
			gotRemoves[got.Mac] = got
		case "/control/dhcp/add_static_lease":
			gotAdds[got.Mac] = got
		}
	}
	if len(gotRemoves) != len(wantRemoves) {
		t.Errorf("removes: got %d leases, want %d", len(gotRemoves), len(wantRemoves))
	}
	for mac, want := range wantRemoves {
		got, ok := gotRemoves[mac]
		if !ok {
			t.Errorf("missing remove for %s", mac)
		} else if got != want {
			t.Errorf("remove %s: got %+v, want %+v", mac, got, want)
		}
	}
	if len(gotAdds) != len(wantAdds) {
		t.Errorf("adds: got %d leases, want %d", len(gotAdds), len(wantAdds))
	}
	for mac, want := range wantAdds {
		got, ok := gotAdds[mac]
		if !ok {
			t.Errorf("missing add for %s", mac)
		} else if got != want {
			t.Errorf("add %s: got %+v, want %+v", mac, got, want)
		}
	}

	// Unknown static leases and dynamic leases are never touched: no call
	// body mentions them, and no delete-all endpoint is called.
	for _, call := range *calls {
		if strings.Contains(call.body, "extra-device") || strings.Contains(call.body, "aa:bb:cc:00:00:01") {
			t.Errorf("call %s touched an unknown static or dynamic lease: %s", call.path, call.body)
		}
	}
}

func TestReconcileEmptyConfig(t *testing.T) {
	c, calls := newTestClient(t, `{"static_leases":[]}`, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	if err := c.reconcile(map[string]staticLease{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if len(*calls) != 2 {
		t.Fatalf("want 2 calls (health + status), got %d: %+v", len(*calls), *calls)
	}
}

func TestHealthFailure(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/control/status", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	var otherCalls int
	mux.HandleFunc("/control/dhcp/status", func(w http.ResponseWriter, r *http.Request) {
		otherCalls++
		w.WriteHeader(http.StatusOK)
	})
	server := httptest.NewServer(mux)
	defer server.Close()

	c := &client{baseURL: server.URL, http: server.Client()}
	if err := c.reconcile(map[string]staticLease{
		"00:e0:4c:03:4b:03": {IP: "10.0.0.3", Hostname: "citadel"},
	}); err == nil {
		t.Fatal("want health-check failure to fail reconcile")
	}
	if otherCalls != 0 {
		t.Fatalf("no further requests expected after health failure, got %d", otherCalls)
	}
}

func TestMutationFailure(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/control/status", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/control/dhcp/status", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"static_leases":[]}`))
	})
	mux.HandleFunc("/control/dhcp/remove_static_lease", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/control/dhcp/add_static_lease", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	server := httptest.NewServer(mux)
	defer server.Close()

	c := &client{baseURL: server.URL, http: server.Client()}
	if err := c.reconcile(map[string]staticLease{
		"00:e0:4c:03:4b:03": {IP: "10.0.0.3", Hostname: "citadel"},
	}); err == nil {
		t.Fatal("want mutation failure to fail reconcile")
	}
}
