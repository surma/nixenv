package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"
)

// --- Configuration ---

type Config struct {
	ListenAddr      string
	DefaultFlakeURL string
	StateDir        string
	WebhookURL      string
}

func configFromFlags() Config {
	cfg := Config{}
	flag.StringVar(&cfg.ListenAddr, "listen", envOr("NIXOS_DEPLOY_LISTEN", ":8080"), "Listen address")
	flag.StringVar(&cfg.DefaultFlakeURL, "flake-url", envOr("NIXOS_DEPLOY_FLAKE_URL", ""), "Default flake URL")
	flag.StringVar(&cfg.StateDir, "state-dir", envOr("NIXOS_DEPLOY_STATE_DIR", "/var/lib/nixos-deploy"), "State directory for logs")
	flag.StringVar(&cfg.WebhookURL, "webhook-url", envOr("NIXOS_DEPLOY_WEBHOOK_URL", ""), "Webhook URL for notifications")
	flag.Parse()
	return cfg
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// --- Deploy types ---

type DeployStatus string

const (
	StatusRunning      DeployStatus = "running"
	StatusSuccess      DeployStatus = "success"
	StatusBuildFailed  DeployStatus = "build-failed"
	StatusSwitchFailed DeployStatus = "switch-failed"
	StatusRollbackFailed DeployStatus = "rollback-failed"
)

type DeployMeta struct {
	ID            string       `json:"id"`
	FlakeURL      string       `json:"flake_url"`
	Status        DeployStatus `json:"status"`
	StartedAt     time.Time    `json:"started_at"`
	FinishedAt    *time.Time   `json:"finished_at,omitempty"`
	PreGeneration int          `json:"pre_generation"`
}

// --- SSE broadcast ---

type Broadcaster struct {
	mu          sync.Mutex
	subscribers map[chan string]struct{}
}

func NewBroadcaster() *Broadcaster {
	return &Broadcaster{subscribers: make(map[chan string]struct{})}
}

func (b *Broadcaster) Subscribe() chan string {
	ch := make(chan string, 256)
	b.mu.Lock()
	b.subscribers[ch] = struct{}{}
	b.mu.Unlock()
	return ch
}

func (b *Broadcaster) Unsubscribe(ch chan string) {
	b.mu.Lock()
	delete(b.subscribers, ch)
	b.mu.Unlock()
	close(ch)
}

func (b *Broadcaster) Send(line string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.subscribers {
		select {
		case ch <- line:
		default:
			// drop if subscriber is slow
		}
	}
}

// --- Deploy engine ---

type DeployEngine struct {
	cfg Config

	mu          sync.Mutex
	activeDeploy *ActiveDeploy
}

type ActiveDeploy struct {
	Meta        DeployMeta
	Broadcaster *Broadcaster
	LogBuf      *LogBuffer
}

// LogBuffer stores log lines and allows replay.
type LogBuffer struct {
	mu    sync.Mutex
	lines []string
}

func (lb *LogBuffer) Append(line string) {
	lb.mu.Lock()
	lb.lines = append(lb.lines, line)
	lb.mu.Unlock()
}

func (lb *LogBuffer) Lines() []string {
	lb.mu.Lock()
	cp := make([]string, len(lb.lines))
	copy(cp, lb.lines)
	lb.mu.Unlock()
	return cp
}

func NewDeployEngine(cfg Config) *DeployEngine {
	return &DeployEngine{cfg: cfg}
}

func (e *DeployEngine) StartDeploy(flakeURL string) (*DeployMeta, error) {
	e.mu.Lock()
	if e.activeDeploy != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("a deploy is already running: %s", e.activeDeploy.Meta.ID)
	}

	id := ulid.Make().String()
	meta := DeployMeta{
		ID:        id,
		FlakeURL:  flakeURL,
		Status:    StatusRunning,
		StartedAt: time.Now().UTC(),
	}

	active := &ActiveDeploy{
		Meta:        meta,
		Broadcaster: NewBroadcaster(),
		LogBuf:      &LogBuffer{},
	}
	e.activeDeploy = active
	e.mu.Unlock()

	go e.runDeploy(active)
	return &meta, nil
}

func (e *DeployEngine) GetActive() *ActiveDeploy {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.activeDeploy
}

func (e *DeployEngine) runDeploy(active *ActiveDeploy) {
	defer func() {
		e.mu.Lock()
		e.activeDeploy = nil
		e.mu.Unlock()
	}()

	meta := &active.Meta

	deploysDir := filepath.Join(e.cfg.StateDir, "deploys", meta.ID)
	if err := os.MkdirAll(deploysDir, 0755); err != nil {
		slog.Error("failed to create deploy dir", "error", err)
		return
	}

	// Open a combined deploy.log that captures everything (status messages + command output).
	// This is used for replay of completed deploys.
	deployLogPath := filepath.Join(deploysDir, "deploy.log")
	deployLogFile, err := os.Create(deployLogPath)
	if err != nil {
		slog.Error("failed to create deploy.log", "error", err)
	}
	defer func() {
		if deployLogFile != nil {
			deployLogFile.Close()
		}
	}()

	broadcast := func(line string) {
		active.LogBuf.Append(line)
		active.Broadcaster.Send(line)
		if deployLogFile != nil {
			fmt.Fprintln(deployLogFile, line)
		}
	}

	// Step 1: Record current generation
	gen, err := currentGeneration()
	if err != nil {
		broadcast(fmt.Sprintf("[deploy] failed to read current generation: %v", err))
		slog.Error("failed to read generation", "error", err)
		meta.PreGeneration = -1
	} else {
		meta.PreGeneration = gen
		broadcast(fmt.Sprintf("[deploy] current NixOS generation: %d", gen))
	}

	// Step 2: Build
	broadcast("[deploy] === BUILD PHASE ===")
	broadcast(fmt.Sprintf("[deploy] nixos-rebuild build --flake %s --refresh", meta.FlakeURL))
	buildLog := filepath.Join(deploysDir, "build.log")
	buildOk := e.runCommand(active, buildLog, deployLogFile, "nixos-rebuild", "build", "--flake", meta.FlakeURL, "--refresh")

	if !buildOk {
		meta.Status = StatusBuildFailed
		broadcast("[deploy] BUILD FAILED")
		e.finishDeploy(active, deploysDir)
		return
	}
	broadcast("[deploy] build succeeded")

	// Step 3: Switch
	broadcast("[deploy] === SWITCH PHASE ===")
	broadcast(fmt.Sprintf("[deploy] nixos-rebuild switch --flake %s --refresh", meta.FlakeURL))
	switchLog := filepath.Join(deploysDir, "switch.log")
	switchOk := e.runCommand(active, switchLog, deployLogFile, "nixos-rebuild", "switch", "--flake", meta.FlakeURL, "--refresh")

	if !switchOk {
		meta.Status = StatusSwitchFailed
		broadcast("[deploy] SWITCH FAILED — initiating rollback")

		// Step 4: Rollback to recorded generation
		if meta.PreGeneration > 0 {
			broadcast(fmt.Sprintf("[deploy] === ROLLBACK to generation %d ===", meta.PreGeneration))
			rollbackLog := filepath.Join(deploysDir, "rollback.log")
			profileLink := fmt.Sprintf("/nix/var/nix/profiles/system-%d-link/bin/switch-to-configuration", meta.PreGeneration)
			rollbackOk := e.runCommand(active, rollbackLog, deployLogFile, profileLink, "switch")
			if !rollbackOk {
				meta.Status = StatusRollbackFailed
				broadcast("[deploy] ROLLBACK FAILED — system may be in inconsistent state")
			} else {
				broadcast("[deploy] rollback succeeded")
			}
		} else {
			broadcast("[deploy] cannot rollback: pre-deploy generation unknown")
		}

		e.finishDeploy(active, deploysDir)
		return
	}

	meta.Status = StatusSuccess
	broadcast("[deploy] === DEPLOY SUCCEEDED ===")
	e.finishDeploy(active, deploysDir)
}

func (e *DeployEngine) finishDeploy(active *ActiveDeploy, deploysDir string) {
	now := time.Now().UTC()
	active.Meta.FinishedAt = &now

	// Write meta.json
	metaPath := filepath.Join(deploysDir, "meta.json")
	data, _ := json.MarshalIndent(active.Meta, "", "  ")
	os.WriteFile(metaPath, data, 0644)

	// Send done event
	active.Broadcaster.Send("[deploy] DONE:" + string(active.Meta.Status))

	// Fire webhook
	if e.cfg.WebhookURL != "" {
		go e.fireWebhook(active.Meta)
	}
}

func (e *DeployEngine) runCommand(active *ActiveDeploy, logFile string, deployLog *os.File, name string, args ...string) bool {
	cmd := exec.Command(name, args...)
	cmd.Env = append(os.Environ(), "NIX_REMOTE=daemon")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		line := fmt.Sprintf("[error] pipe: %v", err)
		active.LogBuf.Append(line)
		active.Broadcaster.Send(line)
		if deployLog != nil {
			fmt.Fprintln(deployLog, line)
		}
		return false
	}
	cmd.Stderr = cmd.Stdout // merge stderr into stdout

	f, err := os.Create(logFile)
	if err != nil {
		slog.Error("failed to create log file", "path", logFile, "error", err)
	}
	defer func() {
		if f != nil {
			f.Close()
		}
	}()

	if err := cmd.Start(); err != nil {
		line := fmt.Sprintf("[error] exec: %v", err)
		active.LogBuf.Append(line)
		active.Broadcaster.Send(line)
		if f != nil {
			fmt.Fprintln(f, line)
		}
		if deployLog != nil {
			fmt.Fprintln(deployLog, line)
		}
		return false
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 256*1024), 256*1024)
	for scanner.Scan() {
		line := scanner.Text()
		active.LogBuf.Append(line)
		active.Broadcaster.Send(line)
		if f != nil {
			fmt.Fprintln(f, line)
		}
		if deployLog != nil {
			fmt.Fprintln(deployLog, line)
		}
	}

	return cmd.Wait() == nil
}

func (e *DeployEngine) fireWebhook(meta DeployMeta) {
	payload, _ := json.Marshal(meta)
	resp, err := http.Post(e.cfg.WebhookURL, "application/json", bytes.NewReader(payload))
	if err != nil {
		slog.Error("webhook failed", "error", err)
		return
	}
	resp.Body.Close()
	slog.Info("webhook sent", "status", resp.StatusCode)
}

// --- Generation detection ---

var generationRe = regexp.MustCompile(`system-(\d+)-link`)

func currentGeneration() (int, error) {
	target, err := os.Readlink("/nix/var/nix/profiles/system")
	if err != nil {
		return 0, fmt.Errorf("readlink /nix/var/nix/profiles/system: %w", err)
	}
	m := generationRe.FindStringSubmatch(filepath.Base(target))
	if m == nil {
		return 0, fmt.Errorf("could not parse generation from %q", target)
	}
	var gen int
	fmt.Sscanf(m[1], "%d", &gen)
	return gen, nil
}

// --- Stored deploys ---

func listDeploys(stateDir string) ([]DeployMeta, error) {
	deploysDir := filepath.Join(stateDir, "deploys")
	entries, err := os.ReadDir(deploysDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var metas []DeployMeta
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		metaPath := filepath.Join(deploysDir, entry.Name(), "meta.json")
		data, err := os.ReadFile(metaPath)
		if err != nil {
			continue
		}
		var m DeployMeta
		if json.Unmarshal(data, &m) == nil {
			metas = append(metas, m)
		}
	}

	// Sort newest first
	sort.Slice(metas, func(i, j int) bool {
		return metas[i].StartedAt.After(metas[j].StartedAt)
	})
	return metas, nil
}

func readDeployLog(stateDir, deployID string) (string, error) {
	// Prefer the combined deploy.log which has full context
	deployLogPath := filepath.Join(stateDir, "deploys", deployID, "deploy.log")
	data, err := os.ReadFile(deployLogPath)
	if err == nil {
		return string(data), nil
	}

	// Fallback to per-phase logs for backwards compat
	deploysDir := filepath.Join(stateDir, "deploys", deployID)
	var combined strings.Builder

	for _, name := range []string{"build.log", "switch.log", "rollback.log"} {
		phaseData, err := os.ReadFile(filepath.Join(deploysDir, name))
		if err != nil {
			continue
		}
		combined.WriteString(fmt.Sprintf("=== %s ===\n", name))
		combined.Write(phaseData)
		combined.WriteString("\n")
	}

	if combined.Len() == 0 {
		return "", fmt.Errorf("no logs found for deploy %s", deployID)
	}
	return combined.String(), nil
}

// --- HTTP handlers ---

func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	io.WriteString(w, indexHTML)
}

func handlePostDeploy(engine *DeployEngine, defaultFlakeURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			FlakeURL string `json:"flake_url"`
		}
		if r.Body != nil {
			json.NewDecoder(r.Body).Decode(&req)
		}
		if req.FlakeURL == "" {
			req.FlakeURL = defaultFlakeURL
		}
		if req.FlakeURL == "" {
			http.Error(w, `{"error":"no flake_url provided and no default configured"}`, http.StatusBadRequest)
			return
		}

		meta, err := engine.StartDeploy(req.FlakeURL)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusConflict)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		json.NewEncoder(w).Encode(meta)
	}
}

func handleDeployStream(engine *DeployEngine, stateDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		deployID := r.PathValue("id")
		if deployID == "" {
			http.Error(w, "missing deploy id", http.StatusBadRequest)
			return
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming not supported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no")

		sendSSE := func(data string) {
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}

		// Check if this is the active deploy
		active := engine.GetActive()
		if active != nil && active.Meta.ID == deployID {
			// Replay existing lines
			for _, line := range active.LogBuf.Lines() {
				sendSSE(line)
			}

			// Subscribe to live updates
			ch := active.Broadcaster.Subscribe()
			defer active.Broadcaster.Unsubscribe(ch)

			for {
				select {
				case line, ok := <-ch:
					if !ok {
						return
					}
					sendSSE(line)
					if strings.HasPrefix(line, "[deploy] DONE:") {
						return
					}
				case <-r.Context().Done():
					return
				}
			}
		}

		// Not active — replay from stored deploy.log
		deployLogPath := filepath.Join(stateDir, "deploys", deployID, "deploy.log")
		data, err := os.ReadFile(deployLogPath)
		if err != nil {
			http.Error(w, fmt.Sprintf("no logs found for deploy %s", deployID), http.StatusNotFound)
			return
		}
		for _, line := range strings.Split(string(data), "\n") {
			if line != "" {
				sendSSE(line)
			}
		}

		// Read stored meta to send done event
		metaPath := filepath.Join(stateDir, "deploys", deployID, "meta.json")
		metaData, err := os.ReadFile(metaPath)
		if err == nil {
			var m DeployMeta
			if json.Unmarshal(metaData, &m) == nil {
				sendSSE("[deploy] DONE:" + string(m.Status))
			}
		}
	}
}

func handleListDeploys(stateDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metas, err := listDeploys(stateDir)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if metas == nil {
			metas = []DeployMeta{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(metas)
	}
}

func handleDeployLog(stateDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		deployID := r.PathValue("id")
		logContent, err := readDeployLog(stateDir, deployID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		io.WriteString(w, logContent)
	}
}

// --- Main ---

func main() {
	cfg := configFromFlags()

	if cfg.DefaultFlakeURL == "" {
		slog.Warn("no default flake URL configured; deploys will require explicit flake_url")
	}

	if err := os.MkdirAll(filepath.Join(cfg.StateDir, "deploys"), 0755); err != nil {
		slog.Error("failed to create state dir", "error", err)
		os.Exit(1)
	}

	engine := NewDeployEngine(cfg)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", handleIndex)
	mux.HandleFunc("POST /api/deploy", handlePostDeploy(engine, cfg.DefaultFlakeURL))
	mux.HandleFunc("GET /api/deploy/{id}/stream", handleDeployStream(engine, cfg.StateDir))
	mux.HandleFunc("GET /api/deploys", handleListDeploys(cfg.StateDir))
	mux.HandleFunc("GET /api/deploys/{id}/log", handleDeployLog(cfg.StateDir))
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	slog.Info("starting nixos-deploy", "listen", cfg.ListenAddr, "flake_url", cfg.DefaultFlakeURL, "state_dir", cfg.StateDir)
	if err := http.ListenAndServe(cfg.ListenAddr, mux); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}
