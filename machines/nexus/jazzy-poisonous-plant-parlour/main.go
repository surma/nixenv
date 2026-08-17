package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	defaultHomeAssistantURL = "http://10.0.0.5:8123"
	defaultEntityID         = "binary_sensor.bean_office_door"
	defaultListenAddress    = "0.0.0.0:8080"
)

type application struct {
	homeAssistantURL string
	entityID         string
	token            string
	httpClient       *http.Client
}

type homeAssistantState struct {
	State string `json:"state"`
}

type pageData struct {
	Answer      string
	AnswerClass string
	Status      string
}

var pageTemplate = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Can Jazz poison himself?</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Impact, Haettenschweiler, "Arial Narrow Bold", sans-serif;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      background: #111;
      color: #f5f5f5;
    }

    main {
      display: grid;
      min-height: 100vh;
      place-content: center;
      gap: 2rem;
      padding: 2rem;
      text-align: center;
    }

    h1 {
      max-width: 12ch;
      margin: 0 auto;
      font-size: clamp(2.5rem, 9vw, 8rem);
      line-height: 0.9;
      text-transform: uppercase;
    }

    .answer {
      font-size: clamp(7rem, 30vw, 24rem);
      line-height: 0.75;
      text-transform: uppercase;
    }

    .answer-yes {
      color: #ff4d4d;
    }

    .answer-no {
      color: #4dff88;
    }

    .answer-unknown {
      color: #ffd24d;
    }

    .status {
      margin: 0;
      color: #aaa;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.9rem;
    }
  </style>
</head>
<body>
  <main>
    <h1>Can Jazz poison himself?</h1>
    <div class="answer {{.AnswerClass}}">{{.Answer}}</div>
    <p class="status">{{.Status}}</p>
  </main>
</body>
</html>
`))

func main() {
	app, err := newApplicationFromEnvironment()
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Addr:              environmentOrDefault("LISTEN_ADDRESS", defaultListenAddress),
		Handler:           http.HandlerFunc(app.serveHTTP),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("listening on %s", server.Addr)
	log.Fatal(server.ListenAndServe())
}

func newApplicationFromEnvironment() (*application, error) {
	tokenFile := os.Getenv("HOME_ASSISTANT_TOKEN_FILE")
	if tokenFile == "" {
		return nil, fmt.Errorf("HOME_ASSISTANT_TOKEN_FILE is required")
	}

	token, err := os.ReadFile(tokenFile)
	if err != nil {
		return nil, fmt.Errorf("read Home Assistant token: %w", err)
	}

	tokenValue := strings.TrimSpace(string(token))
	if tokenValue == "" {
		return nil, fmt.Errorf("Home Assistant token is empty")
	}

	return &application{
		homeAssistantURL: environmentOrDefault("HOME_ASSISTANT_URL", defaultHomeAssistantURL),
		entityID:         environmentOrDefault("HOME_ASSISTANT_ENTITY_ID", defaultEntityID),
		token:            tokenValue,
		httpClient:       &http.Client{Timeout: 5 * time.Second},
	}, nil
}

func (a *application) serveHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	data := a.pageData(r.Context())
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := pageTemplate.Execute(w, data); err != nil {
		log.Printf("render page: %v", err)
	}
}

func (a *application) pageData(ctx context.Context) pageData {
	state, err := a.fetchState(ctx)
	if err != nil {
		log.Printf("read Home Assistant state: %v", err)
		return pageData{
			Answer:      "UNKNOWN",
			AnswerClass: "answer-unknown",
			Status:      "Home Assistant is unavailable. Refresh to try again.",
		}
	}

	answer := answerForState(state)
	return pageData{
		Answer:      answer,
		AnswerClass: "answer-" + strings.ToLower(answer),
		Status:      "Refresh to check again.",
	}
}

func (a *application) fetchState(ctx context.Context) (string, error) {
	endpoint, err := url.JoinPath(a.homeAssistantURL, "api", "states", a.entityID)
	if err != nil {
		return "", fmt.Errorf("build Home Assistant URL: %w", err)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", fmt.Errorf("create Home Assistant request: %w", err)
	}
	request.Header.Set("Authorization", "Bearer "+a.token)

	client := a.httpClient
	if client == nil {
		client = http.DefaultClient
	}
	response, err := client.Do(request)
	if err != nil {
		return "", fmt.Errorf("request Home Assistant state: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("Home Assistant returned %s", response.Status)
	}

	var state homeAssistantState
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&state); err != nil {
		return "", fmt.Errorf("decode Home Assistant state: %w", err)
	}
	state.State = strings.TrimSpace(state.State)
	if state.State == "" {
		return "", fmt.Errorf("Home Assistant returned an empty state")
	}

	return state.State, nil
}

func answerForState(state string) string {
	if state == "on" {
		return "YES"
	}
	return "NO"
}

func environmentOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
