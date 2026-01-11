package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
)

// StateData contains the data stored in the OAuth state parameter
type StateData struct {
	App      string `json:"app"`
	Redirect string `json:"redirect"`
}

// EncodeState encodes and signs the state data
func EncodeState(app, redirect string, secret []byte) (string, error) {
	data := StateData{
		App:      app,
		Redirect: redirect,
	}

	// Marshal to JSON
	jsonData, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("failed to marshal state: %w", err)
	}

	// Create HMAC signature
	h := hmac.New(sha256.New, secret)
	h.Write(jsonData)
	signature := h.Sum(nil)

	// Combine data and signature
	combined := append(jsonData, signature...)

	// Base64 encode
	encoded := base64.URLEncoding.EncodeToString(combined)

	return encoded, nil
}

// DecodeState decodes and verifies the state data
func DecodeState(encoded string, secret []byte) (*StateData, error) {
	// Base64 decode
	combined, err := base64.URLEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("failed to decode state: %w", err)
	}

	// Split data and signature (signature is last 32 bytes)
	if len(combined) < 32 {
		return nil, fmt.Errorf("invalid state: too short")
	}

	jsonData := combined[:len(combined)-32]
	signature := combined[len(combined)-32:]

	// Verify HMAC signature
	h := hmac.New(sha256.New, secret)
	h.Write(jsonData)
	expectedSignature := h.Sum(nil)

	if !hmac.Equal(signature, expectedSignature) {
		return nil, fmt.Errorf("invalid state: signature mismatch")
	}

	// Unmarshal JSON
	var data StateData
	if err := json.Unmarshal(jsonData, &data); err != nil {
		return nil, fmt.Errorf("failed to unmarshal state: %w", err)
	}

	return &data, nil
}
