package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const (
	testOfficeDoor = "binary_sensor.bean_office_door"
	testGardenDoor = "binary_sensor.garden_door_sensor"
)

func TestDoorStateFor(t *testing.T) {
	tests := map[string]doorState{
		"on":          doorOpen,
		"off":         doorClosed,
		"unknown":     doorSilent,
		"unavailable": doorSilent,
	}

	for state, want := range tests {
		t.Run(state, func(t *testing.T) {
			if got := doorStateFor(state); got != want {
				t.Fatalf("doorStateFor(%q) = %q, want %q", state, got, want)
			}
		})
	}
}

func TestVerdict(t *testing.T) {
	tests := []struct {
		name   string
		states []doorState
		want   string
	}{
		{"both closed", []doorState{doorClosed, doorClosed}, "YES"},
		{"office open", []doorState{doorOpen, doorClosed}, "NO"},
		{"garden open", []doorState{doorClosed, doorOpen}, "NO"},
		{"both open", []doorState{doorOpen, doorOpen}, "NO"},
		{"one unreadable, other closed", []doorState{doorUnknown, doorClosed}, "UNKNOWN"},
		{"one unreadable, other open", []doorState{doorUnknown, doorOpen}, "NO"},
		{"both unreadable", []doorState{doorUnknown, doorUnknown}, "UNKNOWN"},
		{"one silent, other closed", []doorState{doorClosed, doorSilent}, "UNKNOWN"},
		{"one silent, other open", []doorState{doorSilent, doorOpen}, "NO"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := verdict(tc.states); got != tc.want {
				t.Fatalf("verdict(%v) = %q, want %q", tc.states, got, tc.want)
			}
		})
	}
}

func TestToneForAnswer(t *testing.T) {
	tests := map[string]string{
		"YES":     "good",
		"NO":      "bad",
		"UNKNOWN": "unknown",
	}

	for answer, want := range tests {
		t.Run(answer, func(t *testing.T) {
			if got := toneForAnswer(answer); got != want {
				t.Fatalf("toneForAnswer(%q) = %q, want %q", answer, got, want)
			}
		})
	}
}

// fakeHomeAssistant serves one state per entity and fails for entities that
// have no state.
func fakeHomeAssistant(t *testing.T, states map[string]string, authorization *string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if authorization != nil {
			*authorization = r.Header.Get("Authorization")
		}
		entityID := strings.TrimPrefix(r.URL.Path, "/api/states/")
		state, ok := states[entityID]
		if !ok {
			http.Error(w, "unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"state":"`+state+`"}`)
	}))
	t.Cleanup(server.Close)
	return server
}

func render(t *testing.T, homeAssistant *httptest.Server) string {
	t.Helper()
	app := &application{
		homeAssistantURL: homeAssistant.URL,
		doors:            officeAndGardenDoors(testOfficeDoor, testGardenDoor),
		token:            "test-token",
		httpClient:       homeAssistant.Client(),
	}

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()
	app.serveHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("response status = %d, want %d", response.Code, http.StatusOK)
	}
	return response.Body.String()
}

func TestServeHTTPCelebratesWhenBothDoorsAreClosed(t *testing.T) {
	var authorization string
	homeAssistant := fakeHomeAssistant(t, map[string]string{
		testOfficeDoor: "off",
		testGardenDoor: "off",
	}, &authorization)

	body := render(t, homeAssistant)

	if authorization != "Bearer test-token" {
		t.Fatalf("authorization = %q, want bearer token", authorization)
	}
	if !strings.Contains(body, ">YES<") {
		t.Fatalf("response does not contain YES:\n%s", body)
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
	if got := strings.Count(body, `class="door door--closed"`); got != 2 {
		t.Fatalf("closed door count = %d, want 2:\n%s", got, body)
	}
}

func TestServeHTTPRaisesTheAlarmForAnOpenGardenDoor(t *testing.T) {
	homeAssistant := fakeHomeAssistant(t, map[string]string{
		testOfficeDoor: "off",
		testGardenDoor: "on",
	}, nil)

	body := render(t, homeAssistant)

	if !strings.Contains(body, ">NO<") {
		t.Fatalf("response does not contain NO:\n%s", body)
	}
	if !strings.Contains(body, `body class="page--bad"`) {
		t.Fatalf("response does not contain the bad page class:\n%s", body)
	}
	if strings.Contains(body, `class="confetti"`) {
		t.Fatalf("bad response contains confetti:\n%s", body)
	}
	if !strings.Contains(body, `class="door door--open"><strong>Garden door:</strong>`) {
		t.Fatalf("response does not report the open garden door:\n%s", body)
	}
	if !strings.Contains(body, `class="door door--closed"><strong>Office door:</strong>`) {
		t.Fatalf("response does not report the closed office door:\n%s", body)
	}
}

func TestServeHTTPRaisesTheAlarmForAnOpenOfficeDoor(t *testing.T) {
	homeAssistant := fakeHomeAssistant(t, map[string]string{
		testOfficeDoor: "on",
		testGardenDoor: "off",
	}, nil)

	body := render(t, homeAssistant)

	if !strings.Contains(body, ">NO<") {
		t.Fatalf("response does not contain NO:\n%s", body)
	}
	if !strings.Contains(body, `class="door door--open"><strong>Office door:</strong>`) {
		t.Fatalf("response does not report the open office door:\n%s", body)
	}
}

func TestServeHTTPShowsUnknownWhenHomeAssistantFails(t *testing.T) {
	homeAssistant := fakeHomeAssistant(t, map[string]string{}, nil)

	body := render(t, homeAssistant)

	if !strings.Contains(body, ">UNKNOWN<") {
		t.Fatalf("response does not contain UNKNOWN:\n%s", body)
	}
	if !strings.Contains(body, `body class="page--unknown"`) {
		t.Fatalf("response does not contain the unknown page class:\n%s", body)
	}
	if strings.Contains(body, `class="confetti"`) {
		t.Fatalf("unknown response contains confetti:\n%s", body)
	}
	if got := strings.Count(body, `class="door door--unknown"`); got != 2 {
		t.Fatalf("unknown door count = %d, want 2:\n%s", got, body)
	}
	if !strings.Contains(body, "Home Assistant is unavailable.") {
		t.Fatalf("response does not say Home Assistant is unavailable:\n%s", body)
	}
}

func TestServeHTTPRefusesAnAllClearFromADeadSensor(t *testing.T) {
	homeAssistant := fakeHomeAssistant(t, map[string]string{
		testOfficeDoor: "off",
		testGardenDoor: "unavailable",
	}, nil)

	body := render(t, homeAssistant)

	if !strings.Contains(body, ">UNKNOWN<") {
		t.Fatalf("a dead sensor must not produce an all-clear:\n%s", body)
	}
	if strings.Contains(body, `class="confetti"`) {
		t.Fatalf("a dead sensor must not produce confetti:\n%s", body)
	}
	if !strings.Contains(body, `class="door door--silent"><strong>Garden door:</strong> No idea. The sensor has stopped reporting.`) {
		t.Fatalf("response does not blame the garden door sensor:\n%s", body)
	}
	if strings.Contains(body, "Home Assistant is unavailable.") {
		t.Fatalf("Home Assistant answered, so the page must not blame it:\n%s", body)
	}
}

func TestServeHTTPStillRaisesTheAlarmWhenOneSensorFails(t *testing.T) {
	homeAssistant := fakeHomeAssistant(t, map[string]string{
		testGardenDoor: "on",
	}, nil)

	body := render(t, homeAssistant)

	if !strings.Contains(body, ">NO<") {
		t.Fatalf("an open garden door must win over an unreadable office door:\n%s", body)
	}
	if !strings.Contains(body, `class="door door--unknown"><strong>Office door:</strong>`) {
		t.Fatalf("response does not report the unreadable office door:\n%s", body)
	}
}
