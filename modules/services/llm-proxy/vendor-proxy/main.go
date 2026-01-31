package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

type KeyManager struct {
	shopifyKeyFile string
	clientKeyFile  string
}

func NewKeyManager(shopifyKeyFile, clientKeyFile string) (*KeyManager, error) {
	// Validate files exist and are readable at startup
	if _, err := os.ReadFile(shopifyKeyFile); err != nil {
		return nil, fmt.Errorf("failed to read shopify key file: %w", err)
	}
	if _, err := os.ReadFile(clientKeyFile); err != nil {
		return nil, fmt.Errorf("failed to read client key file: %w", err)
	}

	return &KeyManager{
		shopifyKeyFile: shopifyKeyFile,
		clientKeyFile:  clientKeyFile,
	}, nil
}

func (km *KeyManager) getShopifyKey() (string, error) {
	keyBytes, err := os.ReadFile(km.shopifyKeyFile)
	if err != nil {
		return "", fmt.Errorf("failed to read shopify key: %w", err)
	}
	return strings.TrimSpace(string(keyBytes)), nil
}

func (km *KeyManager) validateClientKey(r *http.Request) (bool, error) {
	keyBytes, err := os.ReadFile(km.clientKeyFile)
	if err != nil {
		return false, fmt.Errorf("failed to read client key: %w", err)
	}
	clientKey := strings.TrimSpace(string(keyBytes))

	authHeader := r.Header.Get("Authorization")
	expectedAuth := "Bearer " + clientKey
	if authHeader == expectedAuth {
		return true, nil
	}

	apiKeyHeader := r.Header.Get("x-api-key")
	if apiKeyHeader == clientKey {
		return true, nil
	}

	return false, nil
}

type VendorProxy struct {
	keyManager   *KeyManager
	shopifyURL   *url.URL
	reverseProxy *httputil.ReverseProxy
}

func NewVendorProxy(keyManager *KeyManager, shopifyURL string) (*VendorProxy, error) {
	targetURL, err := url.Parse(shopifyURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse shopify URL: %w", err)
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)

	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = targetURL.Host
		req.URL.Scheme = targetURL.Scheme
		req.URL.Host = targetURL.Host
		req.URL.Path = "/vendors" + req.URL.Path
	}

	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error for %s %s: %v", r.Method, r.URL.Path, err)
		w.WriteHeader(http.StatusBadGateway)
		io.WriteString(w, "Bad Gateway\n")
	}

	return &VendorProxy{
		keyManager:   keyManager,
		shopifyURL:   targetURL,
		reverseProxy: proxy,
	}, nil
}

func (vp *VendorProxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	valid, err := vp.keyManager.validateClientKey(r)
	if err != nil {
		log.Printf("Error reading client key: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		io.WriteString(w, "Internal Server Error\n")
		return
	}
	if !valid {
		log.Printf("Unauthorized request from %s to %s %s", r.RemoteAddr, r.Method, r.URL.Path)
		w.WriteHeader(http.StatusUnauthorized)
		io.WriteString(w, "Unauthorized\n")
		return
	}

	shopifyKey, err := vp.keyManager.getShopifyKey()
	if err != nil {
		log.Printf("Error reading shopify key: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		io.WriteString(w, "Internal Server Error\n")
		return
	}
	r.Header.Set("Authorization", "Bearer "+shopifyKey)

	log.Printf("Proxying %s %s to Shopify", r.Method, r.URL.Path)
	vp.reverseProxy.ServeHTTP(w, r)
}

func main() {
	port := os.Getenv("VENDOR_PROXY_PORT")
	if port == "" {
		port = "4001"
	}

	shopifyKeyFile := os.Getenv("SHOPIFY_KEY_FILE")
	if shopifyKeyFile == "" {
		log.Fatal("SHOPIFY_KEY_FILE environment variable is required")
	}

	clientKeyFile := os.Getenv("CLIENT_KEY_FILE")
	if clientKeyFile == "" {
		log.Fatal("CLIENT_KEY_FILE environment variable is required")
	}

	shopifyURL := os.Getenv("SHOPIFY_PROXY_URL")
	if shopifyURL == "" {
		shopifyURL = "https://proxy.shopify.ai"
	}

	keyManager, err := NewKeyManager(shopifyKeyFile, clientKeyFile)
	if err != nil {
		log.Fatalf("Failed to initialize key manager: %v", err)
	}

	vendorProxy, err := NewVendorProxy(keyManager, shopifyURL)
	if err != nil {
		log.Fatalf("Failed to initialize vendor proxy: %v", err)
	}

	addr := ":" + port
	log.Printf("Starting vendor proxy server on %s", addr)
	log.Printf("Proxying to %s/vendors/*", shopifyURL)

	if err := http.ListenAndServe(addr, vendorProxy); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
