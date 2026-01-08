package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Config struct {
	Port       string
	SecretFile string
	KeyFile    string
}

func loadConfig() Config {
	port := os.Getenv("LLM_KEY_RECEIVER_PORT")
	if port == "" {
		port = "8080"
	}

	secretFile := os.Getenv("LLM_KEY_RECEIVER_SECRET_FILE")
	if secretFile == "" {
		log.Fatal("LLM_KEY_RECEIVER_SECRET_FILE environment variable is required")
	}

	keyFile := os.Getenv("LLM_KEY_RECEIVER_KEY_FILE")
	if keyFile == "" {
		log.Fatal("LLM_KEY_RECEIVER_KEY_FILE environment variable is required")
	}

	return Config{
		Port:       port,
		SecretFile: secretFile,
		KeyFile:    keyFile,
	}
}

func readSecret(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read secret file: %w", err)
	}
	return []byte(strings.TrimSpace(string(data))), nil
}

func validateJWT(tokenString string, secret []byte) error {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		// Validate the signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secret, nil
	})

	if err != nil {
		return fmt.Errorf("failed to parse token: %w", err)
	}

	if !token.Valid {
		return fmt.Errorf("invalid token")
	}

	// Check expiry
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return fmt.Errorf("invalid claims format")
	}

	exp, err := claims.GetExpirationTime()
	if err != nil {
		return fmt.Errorf("missing or invalid exp claim: %w", err)
	}

	if exp.Before(time.Now()) {
		return fmt.Errorf("token has expired")
	}

	return nil
}

func writeKey(path string, key string) error {
	// Write to a temp file first, then rename for atomicity
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, []byte(key), 0600); err != nil {
		return fmt.Errorf("failed to write temp file: %w", err)
	}

	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath) // Clean up temp file on failure
		return fmt.Errorf("failed to rename temp file: %w", err)
	}

	return nil
}

func main() {
	cfg := loadConfig()

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/update", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Extract Bearer token from Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Missing Authorization header", http.StatusUnauthorized)
			return
		}

		if !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Invalid Authorization header format", http.StatusUnauthorized)
			return
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")

		// Load and validate JWT
		secret, err := readSecret(cfg.SecretFile)
		if err != nil {
			log.Printf("Error reading secret: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		if err := validateJWT(tokenString, secret); err != nil {
			log.Printf("JWT validation failed: %v", err)
			http.Error(w, "Unauthorized: "+err.Error(), http.StatusUnauthorized)
			return
		}

		// Read the key from request body
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read request body", http.StatusBadRequest)
			return
		}
		defer r.Body.Close()

		key := strings.TrimSpace(string(body))
		if key == "" {
			http.Error(w, "Empty key", http.StatusBadRequest)
			return
		}

		// Write the key to file
		if err := writeKey(cfg.KeyFile, key); err != nil {
			log.Printf("Error writing key: %v", err)
			http.Error(w, "Failed to write key", http.StatusInternalServerError)
			return
		}

		log.Printf("Successfully updated key file: %s", cfg.KeyFile)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("Key updated successfully"))
	})

	addr := ":" + cfg.Port
	log.Printf("Starting key receiver on %s", addr)
	log.Printf("Key file: %s", cfg.KeyFile)
	log.Printf("Secret file: %s", cfg.SecretFile)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
