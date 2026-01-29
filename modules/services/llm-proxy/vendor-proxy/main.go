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
	mu              sync.RWMutex
	shopifyKey      string
	clientKey       string
	shopifyKeyFile  string
	clientKeyFile   string
	watcher         *fsnotify.Watcher
}

func NewKeyManager(shopifyKeyFile, clientKeyFile string) (*KeyManager, error) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, fmt.Errorf("failed to create watcher: %w", err)
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
	shopifyKeyBytes, err := os.ReadFile(km.shopifyKeyFile)
	if err != nil {
		return fmt.Errorf("failed to read shopify key: %w", err)
	}

	clientKeyBytes, err := os.ReadFile(km.clientKeyFile)
	if err != nil {
		return fmt.Errorf("failed to read client key: %w", err)
	}

	km.mu.Lock()
	km.shopifyKey = strings.TrimSpace(string(shopifyKeyBytes))
	km.clientKey = strings.TrimSpace(string(clientKeyBytes))
	km.mu.Unlock()

	log.Printf("Loaded keys: shopify key length=%d, client key length=%d", len(km.shopifyKey), len(km.clientKey))
	return nil
}

func (km *KeyManager) watchKeys() {
	for {
		select {
		case event, ok := <-km.watcher.Events:
			if !ok {
				return
			}
			if event.Op&fsnotify.Write == fsnotify.Write || event.Op&fsnotify.Create == fsnotify.Create {
				log.Printf("Key file modified: %s", event.Name)
				if err := km.loadKeys(); err != nil {
					log.Printf("Error reloading keys: %v", err)
				} else {
					log.Printf("Successfully reloaded keys")
				}
			}
		case err, ok := <-km.watcher.Errors:
			if !ok {
				return
			}
			log.Printf("Watcher error: %v", err)
		}
	}
}

func (km *KeyManager) getShopifyKey() string {
	km.mu.RLock()
	defer km.mu.RUnlock()
	return km.shopifyKey
}

func (km *KeyManager) validateClientKey(authHeader string) bool {
	km.mu.RLock()
	defer km.mu.RUnlock()

	expectedAuth := "Bearer " + km.clientKey
	return authHeader == expectedAuth
}

func (km *KeyManager) Close() error {
	return km.watcher.Close()
}

type VendorProxy struct {
	keyManager  *KeyManager
	shopifyURL  *url.URL
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
	authHeader := r.Header.Get("Authorization")

	if !vp.keyManager.validateClientKey(authHeader) {
		log.Printf("Unauthorized request from %s to %s %s", r.RemoteAddr, r.Method, r.URL.Path)
		w.WriteHeader(http.StatusUnauthorized)
		io.WriteString(w, "Unauthorized\n")
		return
	}

	r.Header.Set("Authorization", "Bearer "+vp.keyManager.getShopifyKey())

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
	defer keyManager.Close()

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
