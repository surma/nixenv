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
	confettiPieceCount      = 600
	confettiBurstWaves      = 20
	glitterPieceCount       = 120
	glitterBurstWaves       = 20
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

type effectPiece struct {
	Side  string
	Burst int
}

type pageData struct {
	Answer         string
	AnswerClass    string
	PageClass      string
	ShowConfetti   bool
	ConfettiPieces []effectPiece
	GlitterPieces  []effectPiece
	Status         string
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

func effectPieces(count, burstWaves int) []effectPiece {
	pieces := make([]effectPiece, count)
	for i := range pieces {
		side := "right"
		if i%2 == 1 {
			side = "left"
		}
		pieces[i] = effectPiece{
			Side:  side,
			Burst: (i*burstWaves)/count + 1,
		}
	}
	return pieces
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

    .confetti,
    .glitter {
      position: fixed;
      inset: 0;
      overflow: hidden;
      pointer-events: none;
    }

    .confetti {
      z-index: 2;
    }

    .glitter {
      z-index: 2;
      mix-blend-mode: screen;
    }

    .confetti-piece {
      position: absolute;
      top: -3rem;
      width: var(--confetti-width, 0.7rem);
      height: var(--confetti-height, 1.5rem);
      border-radius: var(--confetti-radius, 0.2rem);
      background: var(--confetti-color);
      box-shadow: 0 0 0.45rem var(--confetti-color);
      opacity: 0;
      --confetti-wave-delay: 0s;
      --confetti-piece-delay: 0s;
      transform-origin: center;
      will-change: opacity, transform;
      animation: confetti-flight var(--confetti-duration) cubic-bezier(0.16, 0.8, 0.25, 1) calc(var(--confetti-wave-delay) + var(--confetti-piece-delay)) both;
    }

    .confetti-piece--left {
      left: -1.25rem;
      --confetti-direction: 1;
    }

    .confetti-piece--right {
      right: -1.25rem;
      --confetti-direction: -1;
    }

    .confetti-piece--burst-1 { --confetti-wave-delay: 0s; }
    .confetti-piece--burst-2 { --confetti-wave-delay: 0.2s; }
    .confetti-piece--burst-3 { --confetti-wave-delay: 0.4s; }
    .confetti-piece--burst-4 { --confetti-wave-delay: 0.6s; }
    .confetti-piece--burst-5 { --confetti-wave-delay: 0.8s; }
    .confetti-piece--burst-6 { --confetti-wave-delay: 1s; }
    .confetti-piece--burst-7 { --confetti-wave-delay: 1.2s; }
    .confetti-piece--burst-8 { --confetti-wave-delay: 1.4s; }
    .confetti-piece--burst-9 { --confetti-wave-delay: 1.6s; }
    .confetti-piece--burst-10 { --confetti-wave-delay: 1.8s; }
    .confetti-piece--burst-11 { --confetti-wave-delay: 2s; }
    .confetti-piece--burst-12 { --confetti-wave-delay: 2.2s; }
    .confetti-piece--burst-13 { --confetti-wave-delay: 2.4s; }
    .confetti-piece--burst-14 { --confetti-wave-delay: 2.6s; }
    .confetti-piece--burst-15 { --confetti-wave-delay: 2.8s; }
    .confetti-piece--burst-16 { --confetti-wave-delay: 3s; }
    .confetti-piece--burst-17 { --confetti-wave-delay: 3.2s; }
    .confetti-piece--burst-18 { --confetti-wave-delay: 3.4s; }
    .confetti-piece--burst-19 { --confetti-wave-delay: 3.6s; }
    .confetti-piece--burst-20 { --confetti-wave-delay: 3.8s; }

    .confetti-piece:nth-child(18n + 1) { --confetti-color: #ff4d6d; --confetti-duration: 1.45s; --confetti-piece-delay: 0s; --confetti-x: 42vw; --confetti-y: 82vh; --confetti-rotation: 720deg; --confetti-width: 0.8rem; --confetti-height: 1.8rem; --confetti-radius: 0.2rem; }
    .confetti-piece:nth-child(18n + 2) { --confetti-color: #ffd166; --confetti-duration: 2s; --confetti-piece-delay: 0.07s; --confetti-x: 78vw; --confetti-y: 108vh; --confetti-rotation: -980deg; --confetti-width: 0.55rem; --confetti-height: 1.2rem; --confetti-radius: 0.1rem; }
    .confetti-piece:nth-child(18n + 3) { --confetti-color: #06d6a0; --confetti-duration: 1.65s; --confetti-piece-delay: 0.14s; --confetti-x: 30vw; --confetti-y: 65vh; --confetti-rotation: 540deg; --confetti-width: 0.65rem; --confetti-height: 2.4rem; --confetti-radius: 50%; }
    .confetti-piece:nth-child(18n + 4) { --confetti-color: #4cc9f0; --confetti-duration: 2.25s; --confetti-piece-delay: 0.21s; --confetti-x: 112vw; --confetti-y: 132vh; --confetti-rotation: -1260deg; --confetti-width: 1.1rem; --confetti-height: 1.4rem; --confetti-radius: 0.3rem; }
    .confetti-piece:nth-child(18n + 5) { --confetti-color: #c77dff; --confetti-duration: 1.35s; --confetti-piece-delay: 0.28s; --confetti-x: 64vw; --confetti-y: 92vh; --confetti-rotation: 900deg; --confetti-width: 0.95rem; --confetti-height: 2rem; --confetti-radius: 0.15rem; }
    .confetti-piece:nth-child(18n + 6) { --confetti-color: #f72585; --confetti-duration: 2.4s; --confetti-piece-delay: 0.35s; --confetti-x: 24vw; --confetti-y: 118vh; --confetti-rotation: -760deg; --confetti-width: 0.5rem; --confetti-height: 1.1rem; --confetti-radius: 50%; }
    .confetti-piece:nth-child(18n + 7) { --confetti-color: #90be6d; --confetti-duration: 1.8s; --confetti-piece-delay: 0.42s; --confetti-x: 95vw; --confetti-y: 72vh; --confetti-rotation: 1480deg; --confetti-width: 0.75rem; --confetti-height: 1.6rem; --confetti-radius: 0.25rem; }
    .confetti-piece:nth-child(18n + 8) { --confetti-color: #f8961e; --confetti-duration: 2.55s; --confetti-piece-delay: 0.49s; --confetti-x: 46vw; --confetti-y: 145vh; --confetti-rotation: -1560deg; --confetti-width: 1.2rem; --confetti-height: 2.3rem; --confetti-radius: 0.3rem; }
    .confetti-piece:nth-child(18n + 9) { --confetti-color: #00b4d8; --confetti-duration: 1.55s; --confetti-piece-delay: 0.56s; --confetti-x: 72vw; --confetti-y: 58vh; --confetti-rotation: 620deg; --confetti-width: 0.6rem; --confetti-height: 1.9rem; --confetti-radius: 0.1rem; }
    .confetti-piece:nth-child(18n + 10) { --confetti-color: #fee440; --confetti-duration: 2.1s; --confetti-piece-delay: 0.63s; --confetti-x: 120vw; --confetti-y: 112vh; --confetti-rotation: -1100deg; --confetti-width: 0.85rem; --confetti-height: 1.3rem; --confetti-radius: 50%; }
    .confetti-piece:nth-child(18n + 11) { --confetti-color: #ff7096; --confetti-duration: 1.5s; --confetti-piece-delay: 0.7s; --confetti-x: 38vw; --confetti-y: 128vh; --confetti-rotation: 1320deg; --confetti-width: 0.7rem; --confetti-height: 2.6rem; --confetti-radius: 0.2rem; }
    .confetti-piece:nth-child(18n + 12) { --confetti-color: #80ed99; --confetti-duration: 2.7s; --confetti-piece-delay: 0.77s; --confetti-x: 88vw; --confetti-y: 88vh; --confetti-rotation: -1740deg; --confetti-width: 1.25rem; --confetti-height: 1.7rem; --confetti-radius: 0.3rem; }
    .confetti-piece:nth-child(18n + 13) { --confetti-color: #ff9f1c; --confetti-duration: 1.7s; --confetti-piece-delay: 0.84s; --confetti-x: 55vw; --confetti-y: 103vh; --confetti-rotation: 820deg; --confetti-width: 0.45rem; --confetti-height: 1.5rem; --confetti-radius: 0.1rem; }
    .confetti-piece:nth-child(18n + 14) { --confetti-color: #e76f51; --confetti-duration: 2.3s; --confetti-piece-delay: 0.91s; --confetti-x: 106vw; --confetti-y: 70vh; --confetti-rotation: -920deg; --confetti-width: 0.9rem; --confetti-height: 2.8rem; --confetti-radius: 0.2rem; }
    .confetti-piece:nth-child(18n + 15) { --confetti-color: #00f5d4; --confetti-duration: 1.4s; --confetti-piece-delay: 0.98s; --confetti-x: 18vw; --confetti-y: 140vh; --confetti-rotation: 520deg; --confetti-width: 0.7rem; --confetti-height: 1.2rem; --confetti-radius: 50%; }
    .confetti-piece:nth-child(18n + 16) { --confetti-color: #9b5de5; --confetti-duration: 2s; --confetti-piece-delay: 1.05s; --confetti-x: 82vw; --confetti-y: 96vh; --confetti-rotation: -1420deg; --confetti-width: 1.05rem; --confetti-height: 1.9rem; --confetti-radius: 0.25rem; }
    .confetti-piece:nth-child(18n + 17) { --confetti-color: #f15bb5; --confetti-duration: 1.6s; --confetti-piece-delay: 1.12s; --confetti-x: 68vw; --confetti-y: 76vh; --confetti-rotation: 1160deg; --confetti-width: 0.55rem; --confetti-height: 2.1rem; --confetti-radius: 0.1rem; }
    .confetti-piece:nth-child(18n + 18) { --confetti-color: #00bbf9; --confetti-duration: 2.6s; --confetti-piece-delay: 1.19s; --confetti-x: 101vw; --confetti-y: 120vh; --confetti-rotation: -1880deg; --confetti-width: 1.3rem; --confetti-height: 1.5rem; --confetti-radius: 0.3rem; }

    .glitter-piece {
      position: absolute;
      top: -1.5rem;
      width: var(--glitter-size, 0.35rem);
      height: var(--glitter-size, 0.35rem);
      border-radius: 50%;
      background: var(--glitter-color);
      box-shadow: 0 0 0.6rem 0.1rem var(--glitter-color);
      opacity: 0;
      --glitter-wave-delay: 0s;
      --glitter-piece-delay: 0s;
      will-change: opacity, transform;
      animation: glitter-flight var(--glitter-duration) ease-in-out calc(var(--glitter-wave-delay) + var(--glitter-piece-delay)) both;
    }

    .glitter-piece--left {
      left: -0.5rem;
      --glitter-direction: 1;
    }

    .glitter-piece--right {
      right: -0.5rem;
      --glitter-direction: -1;
    }

    .glitter-piece--burst-1 { --glitter-wave-delay: 0s; }
    .glitter-piece--burst-2 { --glitter-wave-delay: 0.2s; }
    .glitter-piece--burst-3 { --glitter-wave-delay: 0.4s; }
    .glitter-piece--burst-4 { --glitter-wave-delay: 0.6s; }
    .glitter-piece--burst-5 { --glitter-wave-delay: 0.8s; }
    .glitter-piece--burst-6 { --glitter-wave-delay: 1s; }
    .glitter-piece--burst-7 { --glitter-wave-delay: 1.2s; }
    .glitter-piece--burst-8 { --glitter-wave-delay: 1.4s; }
    .glitter-piece--burst-9 { --glitter-wave-delay: 1.6s; }
    .glitter-piece--burst-10 { --glitter-wave-delay: 1.8s; }
    .glitter-piece--burst-11 { --glitter-wave-delay: 2s; }
    .glitter-piece--burst-12 { --glitter-wave-delay: 2.2s; }
    .glitter-piece--burst-13 { --glitter-wave-delay: 2.4s; }
    .glitter-piece--burst-14 { --glitter-wave-delay: 2.6s; }
    .glitter-piece--burst-15 { --glitter-wave-delay: 2.8s; }
    .glitter-piece--burst-16 { --glitter-wave-delay: 3s; }
    .glitter-piece--burst-17 { --glitter-wave-delay: 3.2s; }
    .glitter-piece--burst-18 { --glitter-wave-delay: 3.4s; }
    .glitter-piece--burst-19 { --glitter-wave-delay: 3.6s; }
    .glitter-piece--burst-20 { --glitter-wave-delay: 3.8s; }
    .glitter-piece:nth-child(12n + 1) { --glitter-color: #ffe66d; --glitter-duration: 1.6s; --glitter-piece-delay: 0s; --glitter-x: 55vw; --glitter-mid-y: 26vh; --glitter-y: 95vh; }
    .glitter-piece:nth-child(12n + 2) { --glitter-color: #ffffff; --glitter-duration: 1.8s; --glitter-piece-delay: 0.1s; --glitter-x: 98vw; --glitter-mid-y: 32vh; --glitter-y: 120vh; --glitter-size: 0.28rem; }
    .glitter-piece:nth-child(12n + 3) { --glitter-color: #fff3b0; --glitter-duration: 1.45s; --glitter-piece-delay: 0.2s; --glitter-x: 40vw; --glitter-mid-y: 22vh; --glitter-y: 78vh; }
    .glitter-piece:nth-child(12n + 4) { --glitter-color: #ffffff; --glitter-duration: 2.1s; --glitter-piece-delay: 0.3s; --glitter-x: 115vw; --glitter-mid-y: 38vh; --glitter-y: 145vh; --glitter-size: 0.22rem; }
    .glitter-piece:nth-child(12n + 5) { --glitter-color: #ffe66d; --glitter-duration: 1.5s; --glitter-piece-delay: 0.4s; --glitter-x: 70vw; --glitter-mid-y: 28vh; --glitter-y: 100vh; }
    .glitter-piece:nth-child(12n + 6) { --glitter-color: #fff3b0; --glitter-duration: 1.9s; --glitter-piece-delay: 0.5s; --glitter-x: 28vw; --glitter-mid-y: 20vh; --glitter-y: 88vh; --glitter-size: 0.42rem; }
    .glitter-piece:nth-child(12n + 7) { --glitter-color: #ffffff; --glitter-duration: 1.7s; --glitter-piece-delay: 0.6s; --glitter-x: 90vw; --glitter-mid-y: 35vh; --glitter-y: 132vh; }
    .glitter-piece:nth-child(12n + 8) { --glitter-color: #ffe66d; --glitter-duration: 2s; --glitter-piece-delay: 0.7s; --glitter-x: 52vw; --glitter-mid-y: 30vh; --glitter-y: 110vh; --glitter-size: 0.3rem; }
    .glitter-piece:nth-child(12n + 9) { --glitter-color: #ffffff; --glitter-duration: 1.4s; --glitter-piece-delay: 0.8s; --glitter-x: 104vw; --glitter-mid-y: 24vh; --glitter-y: 70vh; }
    .glitter-piece:nth-child(12n + 10) { --glitter-color: #fff3b0; --glitter-duration: 1.8s; --glitter-piece-delay: 0.9s; --glitter-x: 35vw; --glitter-mid-y: 33vh; --glitter-y: 125vh; --glitter-size: 0.25rem; }
    .glitter-piece:nth-child(12n + 11) { --glitter-color: #ffe66d; --glitter-duration: 1.55s; --glitter-piece-delay: 1s; --glitter-x: 78vw; --glitter-mid-y: 27vh; --glitter-y: 92vh; }
    .glitter-piece:nth-child(12n + 12) { --glitter-color: #ffffff; --glitter-duration: 2.2s; --glitter-piece-delay: 1.1s; --glitter-x: 123vw; --glitter-mid-y: 40vh; --glitter-y: 140vh; --glitter-size: 0.3rem; }

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
        transform: translate3d(0, -6vh, 0) rotate(0deg) scale(0.6);
      }
      10% {
        opacity: 1;
        transform: translate3d(0, 6vh, 0) rotate(180deg) scale(1);
      }
      100% {
        opacity: 0;
        transform: translate3d(calc(var(--confetti-x) * var(--confetti-direction)), var(--confetti-y), 0) rotate(var(--confetti-rotation)) scale(0.85);
      }
    }

    @keyframes glitter-flight {
      0% {
        opacity: 0;
        transform: translate3d(0, -5vh, 0) scale(0.1) rotate(0deg);
      }
      18% {
        opacity: 1;
        transform: translate3d(0, 8vh, 0) scale(1.5) rotate(180deg);
      }
      48% {
        opacity: 0.9;
        transform: translate3d(calc(var(--glitter-x) * var(--glitter-direction)), var(--glitter-mid-y), 0) scale(0.9) rotate(420deg);
      }
      100% {
        opacity: 0;
        transform: translate3d(calc(var(--glitter-x) * var(--glitter-direction)), var(--glitter-y), 0) scale(0.05) rotate(720deg);
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
        transform: translate3d(calc(var(--confetti-x) * var(--confetti-direction)), 28vh, 0) rotate(var(--confetti-rotation));
      }

      .glitter-piece {
        animation: none;
        opacity: 0.9;
        transform: translate3d(calc(var(--glitter-x) * var(--glitter-direction)), 28vh, 0) scale(1);
      }
    }
  </style>
</head>
<body class="{{.PageClass}}">
  {{if .ShowConfetti}}
  <div class="confetti" aria-hidden="true">
    {{range .ConfettiPieces}}
    <span class="confetti-piece confetti-piece--{{.Side}} confetti-piece--burst-{{.Burst}}"></span>
    {{end}}
  </div>
  <div class="glitter" aria-hidden="true">
    {{range .GlitterPieces}}
    <span class="glitter-piece glitter-piece--{{.Side}} glitter-piece--burst-{{.Burst}}"></span>
    {{end}}
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
		Answer:         answer,
		AnswerClass:    "answer-" + strings.ToLower(answer),
		PageClass:      pageClassForAnswer(answer),
		ShowConfetti:   answer == "NO",
		ConfettiPieces: effectPieces(confettiPieceCount, confettiBurstWaves),
		GlitterPieces:  effectPieces(glitterPieceCount, glitterBurstWaves),
		Status:         "Refresh to check again.",
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
