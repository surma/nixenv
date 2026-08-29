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

func TestPageClassForAnswer(t *testing.T) {
	tests := map[string]string{
		"YES":   "page--bad",
		"NO":    "page--good",
		"OTHER": "page--unknown",
	}

	for answer, want := range tests {
		t.Run(answer, func(t *testing.T) {
			if got := pageClassForAnswer(answer); got != want {
				t.Fatalf("pageClassForAnswer(%q) = %q, want %q", answer, got, want)
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
	body := response.Body.String()
	if !strings.Contains(body, ">YES<") {
		t.Fatalf("response does not contain YES:\n%s", body)
	}
	if !strings.Contains(body, `body class="page--bad"`) {
		t.Fatalf("response does not contain the bad page class:\n%s", body)
	}
	if strings.Contains(body, `class="confetti"`) {
		t.Fatalf("bad response contains confetti:\n%s", body)
	}
}

func TestServeHTTPShowsConfettiForNo(t *testing.T) {
	homeAssistant := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"state":"off"}`)
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

	body := response.Body.String()
	if !strings.Contains(body, ">NO<") {
		t.Fatalf("response does not contain NO:\n%s", body)
	}
	if !strings.Contains(body, `body class="page--good"`) {
		t.Fatalf("response does not contain the good page class:\n%s", body)
	}
	if !strings.Contains(body, `<div class="confetti" aria-hidden="true">`) {
		t.Fatalf("response does not contain the confetti layer:\n%s", body)
	}
	if got := strings.Count(body, `class="confetti-piece confetti-piece--right confetti-piece--burst-`); got != 300 {
		t.Fatalf("right confetti piece count = %d, want 300", got)
	}
	if got := strings.Count(body, `class="confetti-piece confetti-piece--left confetti-piece--burst-`); got != 300 {
		t.Fatalf("left confetti piece count = %d, want 300", got)
	}
	if got := strings.Count(body, `class="glitter-piece glitter-piece--`); got != 120 {
		t.Fatalf("glitter piece count = %d, want 120", got)
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
	body := response.Body.String()
	if !strings.Contains(body, ">UNKNOWN<") {
		t.Fatalf("response does not contain UNKNOWN:\n%s", body)
	}
	if !strings.Contains(body, `body class="page--unknown"`) {
		t.Fatalf("response does not contain the unknown page class:\n%s", body)
	}
	if strings.Contains(body, `class="confetti"`) {
		t.Fatalf("unknown response contains confetti:\n%s", body)
	}
}
