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
	"sync"

	"github.com/fsnotify/fsnotify"
)

type KeyManager struct {
	mu             sync.RWMutex
	shopifyKey     string
	clientKey      string
	shopifyKeyFile string
	clientKeyFile  string
	watcher        *fsnotify.Watcher
}

func NewKeyManager(shopifyKeyFile, clientKeyFile string) (*KeyManager, error) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, fmt.Errorf("failed to create file watcher: %w", err)
	}

	km := &KeyManager{
		shopifyKeyFile: shopifyKeyFile,
		clientKeyFile:  clientKeyFile,
		watcher:        watcher,
	}

	if err := km.loadKeys(); err != nil {
		return nil, err
	}

	if err := watcher.Add(shopifyKeyFile); err != nil {
		return nil, fmt.Errorf("failed to watch shopify key file: %w", err)
	}

	if err := watcher.Add(clientKeyFile); err != nil {
		return nil, fmt.Errorf("failed to watch client key file: %w", err)
	}

	go km.watchKeys()

	return km, nil
}

func (km *KeyManager) loadKeys() error {
	shopifyKey, err := os.ReadFile(km.shopifyKeyFile)
	if err != nil {
		return fmt.Errorf("failed to read shopify key: %w", err)
	}

	clientKey, err := os.ReadFile(km.clientKeyFile)
	if err != nil {
		return fmt.Errorf("failed to read client key: %w", err)
	}

	km.mu.Lock()
	km.shopifyKey = strings.TrimSpace(string(shopifyKey))
	km.clientKey = strings.TrimSpace(string(clientKey))
	km.mu.Unlock()

	log.Printf("Loaded keys: shopify key (%d chars), client key (%d chars)",
		len(km.shopifyKey), len(km.clientKey))

	return nil
}

func (km *KeyManager) watchKeys() {
	for {
		select {
		case event, ok := <-km.watcher.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Write|fsnotify.Create) != 0 {
				log.Printf("Key file changed: %s, reloading keys", event.Name)
				if err := km.loadKeys(); err != nil {
					log.Printf("Error reloading keys: %v", err)
				} else {
					log.Printf("Keys reloaded successfully")
				}
			}
		case err, ok := <-km.watcher.Errors:
			if !ok {
				return
			}
			log.Printf("File watcher error: %v", err)
		}
	}
}

func (km *KeyManager) getShopifyKey() string {
	km.mu.RLock()
	defer km.mu.RUnlock()
	return km.shopifyKey
}

func (km *KeyManager) validateClientKey(authHeader string) bool {
	authHeader = strings.TrimSpace(authHeader)
	if !strings.HasPrefix(authHeader, "Bearer ") {
		return false
	}

	token := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))

	km.mu.RLock()
	defer km.mu.RUnlock()

	return token == km.clientKey
}

func (km *KeyManager) Close() error {
	return km.watcher.Close()
}

type VendorProxy struct {
	keyManager *KeyManager
	target     *url.URL
	proxy      *httputil.ReverseProxy
}

func NewVendorProxy(keyManager *KeyManager, targetURL string) (*VendorProxy, error) {
	target, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse target URL: %w", err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)

	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = target.Host
		req.URL.Scheme = target.Scheme
		req.URL.Host = target.Host
		req.URL.Path = "/vendors" + req.URL.Path
	}

	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error for %s: %v", r.URL.Path, err)
		http.Error(w, "Bad Gateway", http.StatusBadGateway)
	}

	return &VendorProxy{
		keyManager: keyManager,
		target:     target,
		proxy:      proxy,
	}, nil
}

func (vp *VendorProxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		log.Printf("Missing Authorization header from %s", r.RemoteAddr)
		http.Error(w, "Unauthorized: missing Authorization header", http.StatusUnauthorized)
		return
	}

	if !vp.keyManager.validateClientKey(authHeader) {
		log.Printf("Invalid Authorization header from %s", r.RemoteAddr)
		http.Error(w, "Unauthorized: invalid credentials", http.StatusUnauthorized)
		return
	}

	r.Header.Set("Authorization", "Bearer "+vp.keyManager.getShopifyKey())

	if r.Body != nil {
		bodyBytes, err := io.ReadAll(r.Body)
		if err == nil {
			r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
			r.ContentLength = int64(len(bodyBytes))
		}
	}

	log.Printf("Proxying %s %s to Shopify", r.Method, r.URL.Path)
	vp.proxy.ServeHTTP(w, r)
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

	keyManager, err := NewKeyManager(shopifyKeyFile, clientKeyFile)
	if err != nil {
		log.Fatalf("Failed to initialize key manager: %v", err)
	}
	defer keyManager.Close()

	vendorProxy, err := NewVendorProxy(keyManager, "https://proxy.shopify.ai")
	if err != nil {
		log.Fatalf("Failed to create vendor proxy: %v", err)
	}

	log.Printf("Starting vendor proxy server on port %s", port)
	log.Printf("Shopify key file: %s", shopifyKeyFile)
	log.Printf("Client key file: %s", clientKeyFile)
	log.Printf("Target: https://proxy.shopify.ai/vendors/*")

	if err := http.ListenAndServe(":"+port, vendorProxy); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
