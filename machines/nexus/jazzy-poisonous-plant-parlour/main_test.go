package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAnswerForState(t *testing.T) {
	tests := map[string]string{
		"on":          "YES",
		"off":         "NO",
		"unknown":     "NO",
		"unavailable": "NO",
	}

	for state, want := range tests {
		t.Run(state, func(t *testing.T) {
			if got := answerForState(state); got != want {
				t.Fatalf("answerForState(%q) = %q, want %q", state, got, want)
			}
		})
	}
}

func TestServeHTTPUsesHomeAssistantState(t *testing.T) {
	var authorization string
	homeAssistant := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/states/binary_sensor.bean_office_door" {
			t.Errorf("request path = %q, want sensor state path", r.URL.Path)
		}
		authorization = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"state":"on"}`)
	}))
	defer homeAssistant.Close()

	app := &application{
		homeAssistantURL: homeAssistant.URL,
		entityID:         "binary_sensor.bean_office_door",
		token:            "test-token",
		httpClient:       homeAssistant.Client(),
	}

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()
	app.serveHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("response status = %d, want %d", response.Code, http.StatusOK)
	}
	if authorization != "Bearer test-token" {
		t.Fatalf("authorization = %q, want bearer token", authorization)
	}
	if !strings.Contains(response.Body.String(), ">YES<") {
		t.Fatalf("response does not contain YES:\n%s", response.Body.String())
	}
}

func TestServeHTTPShowsUnknownWhenHomeAssistantFails(t *testing.T) {
	homeAssistant := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "unavailable", http.StatusServiceUnavailable)
	}))
	defer homeAssistant.Close()

	app := &application{
		homeAssistantURL: homeAssistant.URL,
		entityID:         "binary_sensor.bean_office_door",
		token:            "test-token",
		httpClient:       homeAssistant.Client(),
	}

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()
	app.serveHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("response status = %d, want %d", response.Code, http.StatusOK)
	}
	if !strings.Contains(response.Body.String(), ">UNKNOWN<") {
		t.Fatalf("response does not contain UNKNOWN:\n%s", response.Body.String())
	}
}
