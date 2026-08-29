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
	Answer       string
	AnswerClass  string
	PageClass    string
	ShowConfetti bool
	Status       string
}

func pageClassForAnswer(answer string) string {
	switch answer {
	case "YES":
		return "page--bad"
	case "NO":
		return "page--good"
	default:
		return "page--unknown"
	}
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

    html {
      min-height: 100%;
      background: #111;
    }

    body {
      position: relative;
      isolation: isolate;
      overflow-x: hidden;
      margin: 0;
      min-height: 100vh;
      min-height: 100svh;
      background: #111;
      color: #f5f5f5;
    }

    main {
      position: relative;
      z-index: 1;
      display: grid;
      min-height: 100vh;
      min-height: 100svh;
      place-content: center;
      gap: clamp(1.5rem, 5vw, 2rem);
      padding: clamp(1.25rem, 6vw, 2rem);
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

    body.page--bad::before {
      content: "";
      position: fixed;
      inset: 0;
      z-index: 3;
      pointer-events: none;
      border: clamp(0.4rem, 2.3vw, 1.1rem) solid #ff1744;
      box-shadow: inset 0 0 1.5rem rgba(255, 23, 68, 0.8), 0 0 1.5rem rgba(255, 23, 68, 0.8);
      animation: alarm-siren 0.72s ease-in-out infinite;
    }

    .confetti {
      position: fixed;
      inset: 0;
      z-index: 2;
      overflow: hidden;
      pointer-events: none;
    }

    .confetti-piece {
      position: absolute;
      top: -2rem;
      width: 0.65rem;
      height: 1.4rem;
      border-radius: 0.15rem;
      background: var(--confetti-color);
      opacity: 0;
      animation: confetti-flight var(--confetti-duration) cubic-bezier(0.2, 0.8, 0.3, 1) var(--confetti-delay) both;
    }

    .confetti-piece--left {
      left: -1rem;
    }

    .confetti-piece--right {
      right: -1rem;
    }

    .confetti-piece:nth-child(1) { --confetti-color: #ff4d6d; --confetti-duration: 1.8s; --confetti-delay: 0s; --confetti-x: -28vw; --confetti-y: 58vh; --confetti-rotation: 460deg; }
    .confetti-piece:nth-child(2) { --confetti-color: #ffd166; --confetti-duration: 2.2s; --confetti-delay: 0.08s; --confetti-x: 52vw; --confetti-y: 76vh; --confetti-rotation: -620deg; }
    .confetti-piece:nth-child(3) { --confetti-color: #06d6a0; --confetti-duration: 2s; --confetti-delay: 0.16s; --confetti-x: -73vw; --confetti-y: 42vh; --confetti-rotation: 780deg; }
    .confetti-piece:nth-child(4) { --confetti-color: #4cc9f0; --confetti-duration: 2.5s; --confetti-delay: 0.22s; --confetti-x: 91vw; --confetti-y: 88vh; --confetti-rotation: -900deg; }
    .confetti-piece:nth-child(5) { --confetti-color: #c77dff; --confetti-duration: 1.7s; --confetti-delay: 0.3s; --confetti-x: -42vw; --confetti-y: 32vh; --confetti-rotation: 320deg; }
    .confetti-piece:nth-child(6) { --confetti-color: #f72585; --confetti-duration: 2.4s; --confetti-delay: 0.38s; --confetti-x: 66vw; --confetti-y: 96vh; --confetti-rotation: -740deg; }
    .confetti-piece:nth-child(7) { --confetti-color: #90be6d; --confetti-duration: 2.1s; --confetti-delay: 0.44s; --confetti-x: -15vw; --confetti-y: 78vh; --confetti-rotation: 570deg; }
    .confetti-piece:nth-child(8) { --confetti-color: #f8961e; --confetti-duration: 2.6s; --confetti-delay: 0.52s; --confetti-x: 82vw; --confetti-y: 68vh; --confetti-rotation: -1040deg; }
    .confetti-piece:nth-child(9) { --confetti-color: #00b4d8; --confetti-duration: 1.9s; --confetti-delay: 0.6s; --confetti-x: -36vw; --confetti-y: 104vh; --confetti-rotation: 860deg; }
    .confetti-piece:nth-child(10) { --confetti-color: #fee440; --confetti-duration: 2.3s; --confetti-delay: 0.68s; --confetti-x: 60vw; --confetti-y: 52vh; --confetti-rotation: -510deg; }
    .confetti-piece:nth-child(11) { --confetti-color: #ff7096; --confetti-duration: 2s; --confetti-delay: 0.76s; --confetti-x: -97vw; --confetti-y: 82vh; --confetti-rotation: 680deg; }
    .confetti-piece:nth-child(12) { --confetti-color: #80ed99; --confetti-duration: 2.7s; --confetti-delay: 0.84s; --confetti-x: 48vw; --confetti-y: 112vh; --confetti-rotation: -880deg; }
    .confetti-piece:nth-child(3n) { width: 0.4rem; height: 1.8rem; border-radius: 50%; }

    @keyframes alarm-siren {
      0%, 100% {
        opacity: 0.55;
        box-shadow: inset 0 0 1rem rgba(255, 23, 68, 0.65), 0 0 1rem rgba(255, 23, 68, 0.65);
      }
      50% {
        opacity: 1;
        box-shadow: inset 0 0 2.6rem rgba(255, 23, 68, 1), 0 0 2.6rem rgba(255, 23, 68, 1);
      }
    }

    @keyframes confetti-flight {
      0% {
        opacity: 0;
        transform: translate3d(0, -5vh, 0) rotate(0deg);
      }
      12% {
        opacity: 1;
      }
      100% {
        opacity: 0;
        transform: translate3d(var(--confetti-x), var(--confetti-y), 0) rotate(var(--confetti-rotation));
      }
    }

    @media (prefers-reduced-motion: reduce) {
      body.page--bad::before {
        animation: none;
        opacity: 0.85;
      }

      .confetti-piece {
        animation: none;
        opacity: 0.9;
        transform: translate3d(var(--confetti-x), 28vh, 0) rotate(var(--confetti-rotation));
      }
    }
  </style>
</head>
<body class="{{.PageClass}}">
  {{if .ShowConfetti}}
  <div class="confetti" aria-hidden="true">
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
    <span class="confetti-piece confetti-piece--right"></span>
    <span class="confetti-piece confetti-piece--left"></span>
  </div>
  {{end}}
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
			PageClass:   "page--unknown",
			Status:      "Home Assistant is unavailable. Refresh to try again.",
		}
	}

	answer := answerForState(state)
	return pageData{
		Answer:       answer,
		AnswerClass:  "answer-" + strings.ToLower(answer),
		PageClass:    pageClassForAnswer(answer),
		ShowConfetti: answer == "NO",
		Status:       "Refresh to check again.",
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
