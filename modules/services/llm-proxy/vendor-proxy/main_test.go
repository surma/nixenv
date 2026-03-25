package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func writeTempFile(t *testing.T, dir, name, value string) string {
	t.Helper()

	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(value), 0o600); err != nil {
		t.Fatalf("write temp file %s: %v", path, err)
	}

	return path
}

func TestUpstreamPath(t *testing.T) {
	tests := map[string]string{
		"":                              "/vendors",
		"/":                             "/vendors",
		"/openai/v1/chat/completions":   "/vendors/openai/v1/chat/completions",
		"/anthropic/v1/messages":        "/vendors/anthropic/v1/messages",
		"/googlevertexai-global/models": "/vendors/googlevertexai-global/models",
		"/v1/chat/completions":          "/v1/chat/completions",
		"/apis/anthropic/messages":      "/apis/anthropic/messages",
		"/vendors/openai/v1/models":     "/vendors/openai/v1/models",
	}

	for input, want := range tests {
		if got := upstreamPath(input); got != want {
			t.Fatalf("upstreamPath(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestServeHTTPForwardsCustomHeaders(t *testing.T) {
	var receivedPath string
	var receivedHeaders http.Header

	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedPath = r.URL.Path
		receivedHeaders = r.Header.Clone()
		_, _ = io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	tempDir := t.TempDir()
	shopifyKeyFile := writeTempFile(t, tempDir, "shopify-key", "shopify-secret\n")
	clientKeyFile := writeTempFile(t, tempDir, "client-key", "client-secret\n")

	keyManager, err := NewKeyManager(shopifyKeyFile, clientKeyFile)
	if err != nil {
		t.Fatalf("NewKeyManager: %v", err)
	}

	vendorProxy, err := NewVendorProxy(keyManager, upstream.URL)
	if err != nil {
		t.Fatalf("NewVendorProxy: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://proxy.test/v1/chat/completions", nil)
	req.Header.Set("Authorization", "Bearer client-secret")
	req.Header.Set("Shopify-Usage-Tag", `["pi","coding-agent","interactive","session-123"]`)
	req.Header.Set("X-Shopify-Session-Affinity-Header", "pi-session-id")
	req.Header.Set("pi-session-id", "session-123")
	req.Header.Set("anthropic-beta", "context-1m-2025-08-07")

	recorder := httptest.NewRecorder()
	vendorProxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("ServeHTTP status = %d, want %d", recorder.Code, http.StatusOK)
	}

	if receivedPath != "/v1/chat/completions" {
		t.Fatalf("forwarded path = %q, want %q", receivedPath, "/v1/chat/completions")
	}

	if got := receivedHeaders.Get("Authorization"); got != "Bearer shopify-secret" {
		t.Fatalf("Authorization header = %q, want %q", got, "Bearer shopify-secret")
	}

	if got := receivedHeaders.Get("Shopify-Usage-Tag"); got != `["pi","coding-agent","interactive","session-123"]` {
		t.Fatalf("Shopify-Usage-Tag = %q", got)
	}

	if got := receivedHeaders.Get("X-Shopify-Session-Affinity-Header"); got != "pi-session-id" {
		t.Fatalf("X-Shopify-Session-Affinity-Header = %q", got)
	}

	if got := receivedHeaders.Get("pi-session-id"); got != "session-123" {
		t.Fatalf("pi-session-id = %q", got)
	}

	if got := receivedHeaders.Get("anthropic-beta"); got != "context-1m-2025-08-07" {
		t.Fatalf("anthropic-beta = %q", got)
	}
}
