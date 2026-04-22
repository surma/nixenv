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
	"strconv"
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

func configFromEnv() Config {
	return Config{
		ListenAddr:      envOr("NEXUS_ADMIN_LISTEN", ":8080"),
		DefaultFlakeURL: envOr("NEXUS_ADMIN_FLAKE_URL", ""),
		StateDir:        envOr("NEXUS_ADMIN_STATE_DIR", "/var/lib/nexus-admin"),
		WebhookURL:      envOr("NEXUS_ADMIN_WEBHOOK_URL", ""),
	}
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
	StatusRunning        DeployStatus = "running"
	StatusSuccess        DeployStatus = "success"
	StatusBuildFailed    DeployStatus = "build-failed"
	StatusSwitchFailed   DeployStatus = "switch-failed"
	StatusRollbackFailed DeployStatus = "rollback-failed"
	StatusCancelled      DeployStatus = "cancelled"
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
		}
	}
}

// --- Deploy engine ---

// systemdUnitName returns the transient systemd unit name for a deploy.
func systemdUnitName(id string) string {
	return "nexus-admin-job-" + id
}

type DeployEngine struct {
	cfg Config

	mu           sync.Mutex
	activeDeploy *ActiveDeploy
}

type ActiveDeploy struct {
	ID          string
	Broadcaster *Broadcaster
	LogBuf      *LogBuffer
	cancel      func() // stops the systemd transient unit
}

// LogBuffer stores log lines and allows replay.
type LogBuffer struct {
	mu    sync.Mutex
	lines []string
	done  bool
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

func (lb *LogBuffer) MarkDone() {
	lb.mu.Lock()
	lb.done = true
	lb.mu.Unlock()
}

func (lb *LogBuffer) IsDone() bool {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	return lb.done
}

func NewDeployEngine(cfg Config) *DeployEngine {
	return &DeployEngine{cfg: cfg}
}

// RecoverActive checks for in-progress deploys on startup (e.g., after server restart).
// It first marks all orphaned (dead) running deploys as failed, then reconnects to
// at most one still-live deploy.
func (e *DeployEngine) RecoverActive() {
	metas, err := listDeploys(e.cfg.StateDir)
	if err != nil {
		return
	}

	// First pass: clean up all orphaned running deploys whose units are gone.
	// Collect the single still-live deploy (if any) for reconnection.
	var liveID string
	var liveUnit string
	for _, m := range metas {
		if m.Status != StatusRunning {
			continue
		}
		unit := systemdUnitName(m.ID)
		if err := exec.Command("systemctl", "is-active", "--quiet", unit+".service").Run(); err != nil {
			// Unit is not running — mark as failed.
			slog.Warn("found orphaned running deploy, marking as failed", "id", m.ID)
			m.Status = StatusSwitchFailed
			now := time.Now().UTC()
			m.FinishedAt = &now
			deploysDir := filepath.Join(e.cfg.StateDir, "deploys", m.ID)
			data, _ := json.MarshalIndent(m, "", "  ")
			os.WriteFile(filepath.Join(deploysDir, "meta.json"), data, 0644)
			if f, err := os.OpenFile(filepath.Join(deploysDir, "deploy.log"), os.O_APPEND|os.O_WRONLY, 0644); err == nil {
				fmt.Fprintln(f, "[deploy] server restarted — deploy process was interrupted")
				fmt.Fprintln(f, "[deploy] DONE:switch-failed")
				f.Close()
			}
			continue
		}
		// Unit still running — remember the most recent one (list is sorted newest-first)
		if liveID == "" {
			liveID = m.ID
			liveUnit = unit
		}
	}

	// Second pass: reconnect to the live deploy (if any).
	if liveID != "" {
		slog.Info("reconnecting to running deploy", "id", liveID)
		unit := liveUnit
		active := &ActiveDeploy{
			ID:          liveID,
			Broadcaster: NewBroadcaster(),
			LogBuf:      &LogBuffer{},
			cancel: func() {
				exec.Command("systemctl", "stop", unit+".service").Run()
			},
		}
		e.mu.Lock()
		e.activeDeploy = active
		e.mu.Unlock()
		go e.tailDeployLog(active)
	}
}

func (e *DeployEngine) StartDeploy(flakeURL string) (*DeployMeta, error) {
	e.mu.Lock()
	if e.activeDeploy != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("a deploy is already running: %s", e.activeDeploy.ID)
	}

	id := ulid.Make().String()
	meta := DeployMeta{
		ID:        id,
		FlakeURL:  flakeURL,
		Status:    StatusRunning,
		StartedAt: time.Now().UTC(),
	}

	deploysDir := filepath.Join(e.cfg.StateDir, "deploys", id)
	if err := os.MkdirAll(deploysDir, 0755); err != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("failed to create deploy dir: %w", err)
	}

	// Write initial meta.json so the deploy subcommand can read it
	metaPath := filepath.Join(deploysDir, "meta.json")
	data, _ := json.MarshalIndent(meta, "", "  ")
	if err := os.WriteFile(metaPath, data, 0644); err != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("failed to write meta.json: %w", err)
	}

	// Find our own binary path
	self, err := os.Executable()
	if err != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("failed to find own executable: %w", err)
	}

	// Launch the deploy pipeline as a transient systemd unit
	unit := systemdUnitName(id)
	args := []string{
		"systemd-run",
		"--unit=" + unit,
		"--description=NixOS deploy " + id,
		"--collect",        // auto-remove when done
		"--same-dir",       // inherit working directory
		"--setenv=PATH=" + os.Getenv("PATH"),
		"--setenv=HOME=" + os.Getenv("HOME"),
		"--setenv=NIX_REMOTE=daemon",
		self, "run-deploy",
		"--deploy-id=" + id,
		"--flake-url=" + flakeURL,
		"--state-dir=" + e.cfg.StateDir,
	}
	if e.cfg.WebhookURL != "" {
		args = append(args, "--webhook-url="+e.cfg.WebhookURL)
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		e.mu.Unlock()
		return nil, fmt.Errorf("failed to start systemd unit: %w", err)
	}

	active := &ActiveDeploy{
		ID:          id,
		Broadcaster: NewBroadcaster(),
		LogBuf:      &LogBuffer{},
		cancel: func() {
			exec.Command("systemctl", "stop", unit+".service").Run()
		},
	}
	e.activeDeploy = active
	e.mu.Unlock()

	// Start tailing the deploy.log
	go e.tailDeployLog(active)

	return &meta, nil
}

func (e *DeployEngine) CancelDeploy(id string) error {
	e.mu.Lock()
	active := e.activeDeploy
	e.mu.Unlock()

	if active == nil || active.ID != id {
		return fmt.Errorf("no active deploy with id %s", id)
	}

	active.cancel()
	return nil
}

func (e *DeployEngine) GetActive() *ActiveDeploy {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.activeDeploy
}

// tailDeployLog watches the deploy.log file and broadcasts lines to SSE subscribers.
// It keeps running until it sees a DONE line or the file stops growing after the
// systemd unit exits.
//
// NOTE: We use bufio.Reader instead of bufio.Scanner because Scanner caches the
// EOF state internally and never retries the underlying reader once it has seen
// io.EOF. Since deploy.log is a regular file being appended to by a separate
// process (the transient systemd unit), we need a reader that will pick up new
// data on subsequent reads after hitting EOF.
func (e *DeployEngine) tailDeployLog(active *ActiveDeploy) {
	defer func() {
		active.LogBuf.MarkDone()
		e.mu.Lock()
		if e.activeDeploy == active {
			e.activeDeploy = nil
		}
		e.mu.Unlock()
	}()

	deployLogPath := filepath.Join(e.cfg.StateDir, "deploys", active.ID, "deploy.log")

	// Wait for the file to appear (the deploy subcommand creates it)
	for i := 0; i < 100; i++ {
		if _, err := os.Stat(deployLogPath); err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	f, err := os.Open(deployLogPath)
	if err != nil {
		slog.Error("failed to open deploy.log for tailing", "error", err)
		return
	}
	defer f.Close()

	reader := bufio.NewReaderSize(f, 256*1024)
	unit := systemdUnitName(active.ID)

	emit := func(line string) bool {
		active.LogBuf.Append(line)
		active.Broadcaster.Send(line)
		return strings.HasPrefix(line, "[deploy] DONE:")
	}

	// partialLine accumulates bytes when ReadString hits EOF mid-line.
	var partialLine string

	for {
		line, err := reader.ReadString('\n')
		partialLine += line

		if err == nil {
			// Complete line (includes trailing \n).
			trimmed := strings.TrimRight(partialLine, "\r\n")
			partialLine = ""
			if emit(trimmed) {
				return
			}
			continue
		}

		if err != io.EOF {
			slog.Error("error reading deploy.log", "error", err)
			return
		}

		// EOF — no more data right now. Check if the unit is still running.
		if execErr := exec.Command("systemctl", "is-active", "--quiet", unit+".service").Run(); execErr != nil {
			// Unit exited. Drain any remaining data.
			for {
				more, readErr := reader.ReadString('\n')
				partialLine += more
				if idx := strings.Index(partialLine, "\n"); idx >= 0 {
					trimmed := strings.TrimRight(partialLine[:idx], "\r\n")
					partialLine = partialLine[idx+1:]
					if emit(trimmed) {
						return
					}
					continue
				}
				if readErr != nil {
					break
				}
			}
			// Emit any trailing partial line.
			if rest := strings.TrimRight(partialLine, "\r\n"); rest != "" {
				if emit(rest) {
					return
				}
			}

			// If we never saw a DONE line, the process was killed/cancelled.
			deploysDir := filepath.Join(e.cfg.StateDir, "deploys", active.ID)
			metaPath := filepath.Join(deploysDir, "meta.json")
			data, readErr := os.ReadFile(metaPath)
			if readErr == nil {
				var m DeployMeta
				if json.Unmarshal(data, &m) == nil && m.Status != StatusRunning {
					// Deploy subcommand wrote final status
					return
				}
			}
			// Process was killed without writing final status — cancelled.
			if readErr == nil {
				var cm DeployMeta
				if json.Unmarshal(data, &cm) == nil {
					cm.Status = StatusCancelled
					now := time.Now().UTC()
					cm.FinishedAt = &now
					wd, _ := json.MarshalIndent(cm, "", "  ")
					os.WriteFile(metaPath, wd, 0644)
				}
			}
			if dlf, derr := os.OpenFile(
				filepath.Join(deploysDir, "deploy.log"),
				os.O_APPEND|os.O_WRONLY, 0644,
			); derr == nil {
				fmt.Fprintln(dlf, "[deploy] DONE:cancelled")
				dlf.Close()
			}
			active.LogBuf.Append("[deploy] DONE:cancelled")
			active.Broadcaster.Send("[deploy] DONE:cancelled")
			return
		}

		// Unit still running, just no output yet. Wait and retry.
		time.Sleep(200 * time.Millisecond)
	}
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

// --- Deploy subcommand (runs in transient systemd unit) ---

func runDeploySubcommand() {
	var (
		deployID   string
		flakeURL   string
		stateDir   string
		webhookURL string
	)
	fs := flag.NewFlagSet("run-deploy", flag.ExitOnError)
	fs.StringVar(&deployID, "deploy-id", "", "Deploy ID")
	fs.StringVar(&flakeURL, "flake-url", "", "Flake URL")
	fs.StringVar(&stateDir, "state-dir", "/var/lib/nexus-admin", "State directory")
	fs.StringVar(&webhookURL, "webhook-url", "", "Webhook URL")
	fs.Parse(os.Args[2:])

	if deployID == "" || flakeURL == "" {
		slog.Error("deploy-id and flake-url are required")
		os.Exit(1)
	}

	deploysDir := filepath.Join(stateDir, "deploys", deployID)

	// Read initial meta
	metaPath := filepath.Join(deploysDir, "meta.json")
	metaData, err := os.ReadFile(metaPath)
	if err != nil {
		slog.Error("failed to read meta.json", "error", err)
		os.Exit(1)
	}
	var meta DeployMeta
	if err := json.Unmarshal(metaData, &meta); err != nil {
		slog.Error("failed to parse meta.json", "error", err)
		os.Exit(1)
	}

	// Open deploy.log
	deployLogPath := filepath.Join(deploysDir, "deploy.log")
	deployLog, err := os.Create(deployLogPath)
	if err != nil {
		slog.Error("failed to create deploy.log", "error", err)
		os.Exit(1)
	}
	defer deployLog.Close()

	logLine := func(line string) {
		fmt.Fprintln(deployLog, line)
		deployLog.Sync()
	}

	writeMeta := func() {
		data, _ := json.MarshalIndent(meta, "", "  ")
		os.WriteFile(metaPath, data, 0644)
	}

	finish := func() {
		now := time.Now().UTC()
		meta.FinishedAt = &now
		writeMeta()
		logLine("[deploy] DONE:" + string(meta.Status))
		if webhookURL != "" {
			go fireWebhook(webhookURL, meta)
		}
		// Give webhook a moment to fire
		time.Sleep(500 * time.Millisecond)
	}

	// Step 1: Record current generation
	gen, err := currentGeneration()
	if err != nil {
		logLine(fmt.Sprintf("[deploy] failed to read current generation: %v", err))
		meta.PreGeneration = -1
	} else {
		meta.PreGeneration = gen
		logLine(fmt.Sprintf("[deploy] current NixOS generation: %d", gen))
	}
	writeMeta()

	// Step 2: Build
	logLine("[deploy] === BUILD PHASE ===")
	logLine(fmt.Sprintf("[deploy] nixos-rebuild build --flake %s --refresh", flakeURL))
	buildLog := filepath.Join(deploysDir, "build.log")
	if !runPipelineCommand(deployLog, buildLog, "nixos-rebuild", "build", "--flake", flakeURL, "--refresh") {
		meta.Status = StatusBuildFailed
		logLine("[deploy] BUILD FAILED")
		finish()
		return
	}
	logLine("[deploy] build succeeded")

	// Step 3: Switch
	logLine("[deploy] === SWITCH PHASE ===")
	logLine(fmt.Sprintf("[deploy] nixos-rebuild switch --flake %s --refresh", flakeURL))
	switchLog := filepath.Join(deploysDir, "switch.log")
	if !runPipelineCommand(deployLog, switchLog, "nixos-rebuild", "switch", "--flake", flakeURL, "--refresh") {
		meta.Status = StatusSwitchFailed
		logLine("[deploy] SWITCH FAILED — initiating rollback")

		if meta.PreGeneration > 0 {
			logLine(fmt.Sprintf("[deploy] === ROLLBACK to generation %d ===", meta.PreGeneration))
			rollbackLog := filepath.Join(deploysDir, "rollback.log")
			profileLink := fmt.Sprintf("/nix/var/nix/profiles/system-%d-link/bin/switch-to-configuration", meta.PreGeneration)
			if !runPipelineCommand(deployLog, rollbackLog, profileLink, "switch") {
				meta.Status = StatusRollbackFailed
				logLine("[deploy] ROLLBACK FAILED — system may be in inconsistent state")
			} else {
				logLine("[deploy] rollback succeeded")
			}
		} else {
			logLine("[deploy] cannot rollback: pre-deploy generation unknown")
		}

		finish()
		return
	}

	meta.Status = StatusSuccess
	logLine("[deploy] === DEPLOY SUCCEEDED ===")
	finish()
}

// runPipelineCommand executes a command, writing output to both a phase log and the deploy log.
func runPipelineCommand(deployLog *os.File, phaseLogPath string, name string, args ...string) bool {
	cmd := exec.Command(name, args...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		line := fmt.Sprintf("[error] pipe: %v", err)
		fmt.Fprintln(deployLog, line)
		deployLog.Sync()
		return false
	}
	cmd.Stderr = cmd.Stdout

	phaseLog, err := os.Create(phaseLogPath)
	if err != nil {
		slog.Error("failed to create phase log", "path", phaseLogPath, "error", err)
	}
	defer func() {
		if phaseLog != nil {
			phaseLog.Close()
		}
	}()

	if err := cmd.Start(); err != nil {
		line := fmt.Sprintf("[error] exec: %v", err)
		fmt.Fprintln(deployLog, line)
		deployLog.Sync()
		if phaseLog != nil {
			fmt.Fprintln(phaseLog, line)
		}
		return false
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 256*1024), 256*1024)
	for scanner.Scan() {
		line := scanner.Text()
		fmt.Fprintln(deployLog, line)
		deployLog.Sync()
		if phaseLog != nil {
			fmt.Fprintln(phaseLog, line)
		}
	}

	return cmd.Wait() == nil
}

func fireWebhook(webhookURL string, meta DeployMeta) {
	payload, _ := json.Marshal(meta)
	resp, err := http.Post(webhookURL, "application/json", bytes.NewReader(payload))
	if err != nil {
		slog.Error("webhook failed", "error", err)
		return
	}
	resp.Body.Close()
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

	sort.Slice(metas, func(i, j int) bool {
		return metas[i].StartedAt.After(metas[j].StartedAt)
	})
	return metas, nil
}

func readDeployLog(stateDir, deployID string) (string, error) {
	deployLogPath := filepath.Join(stateDir, "deploys", deployID, "deploy.log")
	data, err := os.ReadFile(deployLogPath)
	if err == nil {
		return string(data), nil
	}

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

func handleCancelDeploy(engine *DeployEngine) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		deployID := r.PathValue("id")
		if err := engine.CancelDeploy(deployID); err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "cancelling"})
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
		if active != nil && active.ID == deployID {
			// Replay existing lines
			for _, line := range active.LogBuf.Lines() {
				sendSSE(line)
			}

			if active.LogBuf.IsDone() {
				return
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

func handleListDeploys(engine *DeployEngine, stateDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metas, err := listDeploys(stateDir)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if metas == nil {
			metas = []DeployMeta{}
		}

		// Inject active deploy ID so the UI knows which one is live
		w.Header().Set("Content-Type", "application/json")
		active := engine.GetActive()
		type listResponse struct {
			ActiveID string       `json:"active_id,omitempty"`
			Deploys  []DeployMeta `json:"deploys"`
		}
		resp := listResponse{Deploys: metas}
		if active != nil {
			resp.ActiveID = active.ID
		}
		json.NewEncoder(w).Encode(resp)
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

// --- Journal / systemd handlers ---

// handleContainers lists available systemd-nspawn machines.
func handleContainers() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cmd := exec.Command("machinectl", "list", "--no-legend", "--no-pager")
		out, err := cmd.Output()
		if err != nil {
			http.Error(w, fmt.Sprintf("machinectl failed: %v", err), http.StatusInternalServerError)
			return
		}

		var containers []string
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// machinectl list columns: MACHINE CLASS SERVICE OS VERSION ADDRESSES
			fields := strings.Fields(line)
			if len(fields) >= 1 {
				containers = append(containers, fields[0])
			}
		}
		if containers == nil {
			containers = []string{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"containers": containers})
	}
}

// handleUnits lists systemd service units on the host or inside a container.
func handleUnits() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		container := r.URL.Query().Get("container")

		args := []string{"list-units", "--type=service", "--no-pager", "--no-legend"}
		if container != "" {
			args = append([]string{"-M", container}, args...)
		}

		cmd := exec.Command("systemctl", args...)
		out, err := cmd.Output()
		if err != nil {
			http.Error(w, fmt.Sprintf("systemctl failed: %v", err), http.StatusInternalServerError)
			return
		}

		type UnitInfo struct {
			Unit   string `json:"unit"`
			Load   string `json:"load"`
			Active string `json:"active"`
			Sub    string `json:"sub"`
			Desc   string `json:"description"`
		}

		var units []UnitInfo
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// systemctl list-units columns: UNIT LOAD ACTIVE SUB DESCRIPTION...
			fields := strings.Fields(line)
			if len(fields) < 4 {
				continue
			}
			desc := ""
			if len(fields) > 4 {
				desc = strings.Join(fields[4:], " ")
			}
			units = append(units, UnitInfo{
				Unit:   fields[0],
				Load:   fields[1],
				Active: fields[2],
				Sub:    fields[3],
				Desc:   desc,
			})
		}
		if units == nil {
			units = []UnitInfo{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"units": units})
	}
}

// handleLogs fetches journal logs for a specific unit.
func handleLogs() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		unit := r.URL.Query().Get("unit")
		if unit == "" {
			http.Error(w, `{"error":"unit parameter is required"}`, http.StatusBadRequest)
			return
		}

		container := r.URL.Query().Get("container")
		linesStr := r.URL.Query().Get("lines")
		boot := r.URL.Query().Get("boot")
		since := r.URL.Query().Get("since")
		until := r.URL.Query().Get("until")

		lines := 100
		if linesStr != "" {
			if n, err := strconv.Atoi(linesStr); err == nil && n > 0 {
				lines = n
			}
		}
		// Cap at a reasonable maximum to avoid OOM
		if lines > 10000 {
			lines = 10000
		}

		args := []string{"-u", unit, "--no-pager", "-n", strconv.Itoa(lines), "-o", "short-iso"}
		if container != "" {
			args = append([]string{"-M", container}, args...)
		}
		if boot == "true" || boot == "1" {
			args = append(args, "-b")
		}
		if since != "" {
			args = append(args, "--since="+since)
		}
		if until != "" {
			args = append(args, "--until="+until)
		}

		cmd := exec.Command("journalctl", args...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			// journalctl returns exit 1 when no entries are found, which is not
			// really an error. Return the output either way so the caller sees
			// the "No entries" message.
			if len(out) == 0 {
				http.Error(w, fmt.Sprintf("journalctl failed: %v", err), http.StatusInternalServerError)
				return
			}
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(out)
	}
}

// --- Main ---

func main() {
	// Check for subcommand
	if len(os.Args) > 1 && os.Args[1] == "run-deploy" {
		runDeploySubcommand()
		return
	}

	cfg := configFromEnv()

	// Also support flags for backwards compat / manual runs
	flag.StringVar(&cfg.ListenAddr, "listen", cfg.ListenAddr, "Listen address")
	flag.StringVar(&cfg.DefaultFlakeURL, "flake-url", cfg.DefaultFlakeURL, "Default flake URL")
	flag.StringVar(&cfg.StateDir, "state-dir", cfg.StateDir, "State directory for logs")
	flag.StringVar(&cfg.WebhookURL, "webhook-url", cfg.WebhookURL, "Webhook URL for notifications")
	flag.Parse()

	if cfg.DefaultFlakeURL == "" {
		slog.Warn("no default flake URL configured; deploys will require explicit flake_url")
	}

	if err := os.MkdirAll(filepath.Join(cfg.StateDir, "deploys"), 0755); err != nil {
		slog.Error("failed to create state dir", "error", err)
		os.Exit(1)
	}

	engine := NewDeployEngine(cfg)

	// Check for any deploy that was running when we last exited
	engine.RecoverActive()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", handleIndex)
	mux.HandleFunc("POST /api/deploy", handlePostDeploy(engine, cfg.DefaultFlakeURL))
	mux.HandleFunc("POST /api/deploy/{id}/cancel", handleCancelDeploy(engine))
	mux.HandleFunc("GET /api/deploy/{id}/stream", handleDeployStream(engine, cfg.StateDir))
	mux.HandleFunc("GET /api/deploys", handleListDeploys(engine, cfg.StateDir))
	mux.HandleFunc("GET /api/deploys/{id}/log", handleDeployLog(cfg.StateDir))
	mux.HandleFunc("GET /api/containers", handleContainers())
	mux.HandleFunc("GET /api/units", handleUnits())
	mux.HandleFunc("GET /api/logs", handleLogs())
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	slog.Info("starting nexus-admin", "listen", cfg.ListenAddr, "flake_url", cfg.DefaultFlakeURL, "state_dir", cfg.StateDir)
	if err := http.ListenAndServe(cfg.ListenAddr, mux); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}
