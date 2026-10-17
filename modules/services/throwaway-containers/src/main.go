// Command throwaway-containers runs throwaway NixOS containers: boxes made
// with the stock nixos-container tool, each with a mandatory TTL, an
// ephemeral root and no published ports. HTTP API: the handlers at the end
// of this file (spec: Sausage site research/nixos-containers-api).
//
//	throwaway-containers serve [flags]   HTTP API (reaps expired boxes on start)
//	throwaway-containers reap  [flags]   destroy expired tc-* boxes (minutely timer)
//	throwaway-containers wipe  [flags]   destroy every tc-* box (once at boot)
//
// It only ever touches containers named tc-<6 chars>. The state of each box
// lives in <state-dir>/<id>/ (meta.json is the truth for the TTL).
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	maxOutput   = 1 << 20  // exec stdout/stderr cap
	maxFile     = 64 << 20 // file read/write cap
	maxLog      = 64 << 10 // GET /log returns this much of the tail
	maxExecSecs = 1800
)

type options struct {
	port       int
	defaultTTL int
	stateDir   string
	confDir    string
	rootDir    string
	nixpkgs    string
}

var (
	opt  options
	idRe = regexp.MustCompile(`^tc-[a-z0-9]{6}$`)
	// mu guards read-modify-write of meta.json files in this process.
	mu sync.Mutex
)

// Container is what GET /containers/<id> returns; it is also meta.json.
type Container struct {
	ID        string          `json:"id"`
	State     string          `json:"state"` // creating|running|updating|failed
	Address   string          `json:"address"`
	CreatedAt time.Time       `json:"created_at"`
	ExpiresAt time.Time       `json:"expires_at"`
	Owner     string          `json:"owner"`
	Config    json.RawMessage `json:"config"`
	Error     *string         `json:"error"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: throwaway-containers serve|reap|wipe [flags]")
		os.Exit(2)
	}
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	fs.IntVar(&opt.port, "port", 8093, "HTTP port")
	fs.IntVar(&opt.defaultTTL, "default-ttl", 3600, "default TTL in seconds")
	fs.StringVar(&opt.stateDir, "state-dir", "/var/lib/throwaway-containers", "state directory")
	fs.StringVar(&opt.confDir, "conf-dir", "/etc/nixos-containers", "nixos-container configuration directory")
	fs.StringVar(&opt.rootDir, "root-dir", "/var/lib/nixos-containers", "nixos-container root directory")
	fs.StringVar(&opt.nixpkgs, "nixpkgs", "", "nixpkgs source to build nixos configs with (default <nixpkgs>)")
	fs.Parse(os.Args[2:])
	if err := os.MkdirAll(opt.stateDir, 0o700); err != nil {
		log.Fatal(err)
	}
	switch os.Args[1] {
	case "serve":
		serve()
	case "reap":
		reap()
	case "wipe":
		wipe()
	default:
		fmt.Fprintln(os.Stderr, "unknown command", os.Args[1])
		os.Exit(2)
	}
}

// ---- state ----

func boxDir(id string) string { return filepath.Join(opt.stateDir, id) }

func readMeta(id string) *Container {
	b, err := os.ReadFile(filepath.Join(boxDir(id), "meta.json"))
	if err != nil {
		return nil
	}
	var c Container
	if json.Unmarshal(b, &c) != nil {
		return nil
	}
	return &c
}

func writeMeta(c *Container) error {
	dir := boxDir(c.ID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := filepath.Join(dir, "meta.json.tmp")
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(dir, "meta.json"))
}

// updateMeta changes an existing meta.json; false if the box is gone.
func updateMeta(id string, fn func(c *Container)) bool {
	mu.Lock()
	defer mu.Unlock()
	c := readMeta(id)
	if c == nil {
		return false
	}
	fn(c)
	if err := writeMeta(c); err != nil {
		log.Printf("%s: write meta: %v", id, err)
	}
	return true
}

func listMeta() []*Container {
	out := []*Container{}
	ents, _ := os.ReadDir(opt.stateDir)
	for _, e := range ents {
		if !idRe.MatchString(e.Name()) {
			continue
		}
		if c := readMeta(e.Name()); c != nil {
			out = append(out, c)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out
}

// listContainers returns the tc-* containers nixos-container knows about.
func listContainers() []string {
	var out []string
	ents, _ := os.ReadDir(opt.confDir)
	for _, e := range ents {
		id, ok := strings.CutSuffix(e.Name(), ".conf")
		if ok && idRe.MatchString(id) {
			out = append(out, id)
		}
	}
	return out
}

func containerExists(id string) bool {
	_, err := os.Stat(filepath.Join(opt.confDir, id+".conf"))
	return err == nil
}

func confValue(id, key string) string {
	b, err := os.ReadFile(filepath.Join(opt.confDir, id+".conf"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, key+"="); ok {
			return strings.Trim(v, `"`)
		}
	}
	return ""
}

func newID() string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	for {
		b := make([]byte, 6)
		if _, err := rand.Read(b); err != nil {
			panic(err)
		}
		for i := range b {
			b[i] = alphabet[int(b[i])%len(alphabet)]
		}
		id := "tc-" + string(b)
		if _, err := os.Stat(boxDir(id)); os.IsNotExist(err) && !containerExists(id) {
			return id
		}
	}
}

// ---- commands ----

func run(ctx context.Context, logw io.Writer, name string, args ...string) error {
	fmt.Fprintf(logw, "$ %s %s\n", name, strings.Join(args, " "))
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = logw
	cmd.Stderr = logw
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s %s: %v (see /log)", name, args[0], err)
	}
	return nil
}

func openLog(id string) *os.File {
	f, err := os.OpenFile(filepath.Join(boxDir(id), "build.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		log.Printf("%s: open log: %v", id, err)
		f, _ = os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	}
	return f
}

// destroyContainer removes the nixos-container (if any) and leftover
// ephemeral root copies, but keeps the state dir (meta + log).
func destroyContainer(id string, logw io.Writer) {
	if containerExists(id) {
		if err := run(context.Background(), logw, "nixos-container", "destroy", id); err != nil {
			log.Printf("%s: destroy: %v", id, err)
		}
	}
	removeEphemeralCopies("machine." + id)
}

// destroy removes a box completely.
func destroy(id string) {
	log.Printf("%s: destroying", id)
	destroyContainer(id, os.Stderr)
	mu.Lock()
	defer mu.Unlock()
	if err := os.RemoveAll(boxDir(id)); err != nil {
		log.Printf("%s: remove state: %v", id, err)
	}
}

// removeEphemeralCopies deletes nspawn's temporary root copies
// (<root-dir>/.#<prefix>*). nspawn removes them on stop; after a power cut
// they stay behind. var/empty is immutable on NixOS, so chattr -i first.
func removeEphemeralCopies(prefix string) {
	matches, _ := filepath.Glob(filepath.Join(opt.rootDir, ".#"+prefix+"*"))
	for _, p := range matches {
		_ = exec.Command("chattr", "-i", filepath.Join(p, "var/empty")).Run()
		if err := os.RemoveAll(p); err != nil {
			log.Printf("remove %s: %v", p, err)
		}
	}
}

func reap() {
	now := time.Now()
	seen := map[string]bool{}
	for _, id := range listContainers() {
		seen[id] = true
		if c := readMeta(id); c == nil || now.After(c.ExpiresAt) {
			destroy(id)
		}
	}
	ents, _ := os.ReadDir(opt.stateDir)
	for _, e := range ents {
		id := e.Name()
		if !idRe.MatchString(id) || seen[id] {
			continue
		}
		// Without a container: keep it until it expires (a build may be
		// running, or a failed box keeps its log), then drop it.
		if c := readMeta(id); c == nil || now.After(c.ExpiresAt) {
			destroy(id)
		}
	}
}

func wipe() {
	for _, id := range listContainers() {
		destroy(id)
	}
	removeEphemeralCopies("machine.tc-")
	ents, _ := os.ReadDir(opt.stateDir)
	for _, e := range ents {
		if idRe.MatchString(e.Name()) {
			destroy(e.Name())
		}
	}
}

// ---- building and lifecycle ----

type boxConfig struct {
	Flake  string          `json:"flake,omitempty"`
	Nixos  json.RawMessage `json:"nixos,omitempty"`
	System string          `json:"system,omitempty"`
}

func parseConfig(raw json.RawMessage) (*boxConfig, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return nil, errors.New("config is required: {flake}, {nixos} or {system}")
	}
	var bc boxConfig
	if err := json.Unmarshal(raw, &bc); err != nil {
		return nil, fmt.Errorf("bad config: %v", err)
	}
	if string(bc.Nixos) == "null" {
		bc.Nixos = nil
	}
	n := 0
	if bc.Flake != "" {
		n++
	}
	if len(bc.Nixos) > 0 {
		n++
		if c := bc.Nixos[0]; c != '"' && c != '{' {
			return nil, errors.New("config.nixos must be module text or a JSON object")
		}
	}
	if bc.System != "" {
		n++
		if !strings.HasPrefix(bc.System, "/nix/store/") {
			return nil, errors.New("config.system must be a /nix/store path")
		}
	}
	if n != 1 {
		return nil, errors.New("config needs exactly one of flake, nixos, system")
	}
	return &bc, nil
}

const wrapperTmpl = `# Generated by throwaway-containers for %[2]s.
{ lib, ... }:
{
  imports = [ %[1]s ];
  boot.isNspawnContainer = true;
  networking.hostName = lib.mkDefault "%[2]s";
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkDefault false;
  networking.nameservers = lib.mkDefault [ "1.1.1.1" "9.9.9.9" ];
  system.stateVersion = lib.mkDefault lib.trivial.release;
}
`

// build returns the store path of the container's NixOS system.
func build(ctx context.Context, id string, bc *boxConfig, logw io.Writer) (string, error) {
	dir := boxDir(id)
	out := filepath.Join(dir, "result")
	switch {
	case bc.System != "":
		if _, err := os.Stat(bc.System); err != nil {
			return "", fmt.Errorf("system path: %v", err)
		}
		return bc.System, nil
	case bc.Flake != "":
		ref, attr := bc.Flake, "container"
		if i := strings.LastIndex(ref, "#"); i >= 0 {
			ref, attr = ref[:i], ref[i+1:]
		}
		installable := fmt.Sprintf("%s#nixosConfigurations.%q.config.system.build.toplevel", ref, attr)
		if err := run(ctx, logw, "nix", "--extra-experimental-features", "nix-command flakes",
			"build", "--print-build-logs", "--out-link", out, installable); err != nil {
			return "", err
		}
	default:
		var text string
		imp := "./module.nix"
		if json.Unmarshal(bc.Nixos, &text) == nil {
			if err := os.WriteFile(filepath.Join(dir, "module.nix"), []byte(text), 0o600); err != nil {
				return "", err
			}
		} else {
			if err := os.WriteFile(filepath.Join(dir, "config.json"), bc.Nixos, 0o600); err != nil {
				return "", err
			}
			imp = "(builtins.fromJSON (builtins.readFile ./config.json))"
		}
		wrapper := filepath.Join(dir, "wrapper.nix")
		if err := os.WriteFile(wrapper, []byte(fmt.Sprintf(wrapperTmpl, imp, id)), 0o600); err != nil {
			return "", err
		}
		nixos := "<nixpkgs/nixos>"
		if opt.nixpkgs != "" {
			nixos = filepath.Join(opt.nixpkgs, "nixos")
		}
		if err := run(ctx, logw, "nix-build", nixos, "--arg", "configuration", wrapper,
			"-A", "system", "--out-link", out); err != nil {
			return "", err
		}
	}
	p, err := os.Readlink(out)
	if err != nil {
		return "", fmt.Errorf("build result: %v", err)
	}
	return p, nil
}

// makeEphemeral makes container@<id> run systemd-nspawn --ephemeral: the
// unit passes $EXTRA_NSPAWN_FLAGS from the .conf straight to nspawn. nspawn
// allows it next to the template's --link-journal=try-guest (try-* modes are
// exempt) and links no journal in ephemeral mode.
func makeEphemeral(id string) error {
	f, err := os.OpenFile(filepath.Join(opt.confDir, id+".conf"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, `EXTRA_NSPAWN_FLAGS="--ephemeral"`)
	return err
}

func createBox(id string, bc *boxConfig) {
	logw := openLog(id)
	defer logw.Close()
	ctx := context.Background()
	fail := func(err error) {
		log.Printf("%s: create failed: %v", id, err)
		fmt.Fprintf(logw, "error: %v\n", err)
		destroyContainer(id, logw)
		updateMeta(id, func(c *Container) {
			msg := err.Error()
			c.State, c.Error = "failed", &msg
		})
	}
	sys, err := build(ctx, id, bc, logw)
	if err != nil {
		fail(err)
		return
	}
	if readMeta(id) == nil {
		fmt.Fprintln(logw, "deleted while building")
		return
	}
	// Never --auto-start, --port or --bridge: the box gets a private veth
	// (10.233.N.2) and AUTO_START=0.
	if err := run(ctx, logw, "nixos-container", "create", id, "--system-path", sys); err != nil {
		fail(err)
		return
	}
	if err := makeEphemeral(id); err != nil {
		fail(err)
		return
	}
	if err := run(ctx, logw, "nixos-container", "start", id); err != nil {
		fail(err)
		return
	}
	addr := confValue(id, "LOCAL_ADDRESS")
	if !updateMeta(id, func(c *Container) { c.State, c.Address, c.Error = "running", addr, nil }) {
		destroyContainer(id, logw) // deleted meanwhile
		return
	}
	fmt.Fprintln(logw, "running at", addr)
	log.Printf("%s: running at %s", id, addr)
}

func reconfigureBox(id string, bc *boxConfig, raw json.RawMessage) {
	logw := openLog(id)
	defer logw.Close()
	ctx := context.Background()
	fmt.Fprintln(logw, "--- reconfigure")
	err := func() error {
		sys, err := build(ctx, id, bc, logw)
		if err != nil {
			return err
		}
		profile := "/nix/var/nix/profiles/per-container/" + id + "/system"
		if err := run(ctx, logw, "nix-env", "-p", profile, "--set", sys); err != nil {
			return err
		}
		// ExecReload = switch-to-configuration test inside the box.
		return run(ctx, logw, "systemctl", "reload", "container@"+id+".service")
	}()
	updateMeta(id, func(c *Container) {
		c.State = "running"
		if err != nil {
			msg := err.Error()
			c.Error = &msg
		} else {
			c.Config, c.Error = raw, nil
		}
	})
	if err != nil {
		log.Printf("%s: reconfigure failed: %v", id, err)
		fmt.Fprintf(logw, "error: %v\n", err)
	}
}

// ---- exec ----

type limitedBuffer struct {
	buf       bytes.Buffer
	max       int
	truncated bool
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if room := b.max - b.buf.Len(); room < len(p) {
		if room > 0 {
			b.buf.Write(p[:room])
		}
		b.truncated = true
		return len(p), nil
	}
	return b.buf.Write(p)
}

type execResult struct {
	Exit      int    `json:"exit"`
	Stdout    string `json:"stdout"`
	Stderr    string `json:"stderr"`
	TimedOut  bool   `json:"timed_out"`
	Truncated bool   `json:"truncated"`
	stdout    []byte
}

// execIn runs argv as root inside the box. The command is wrapped in
// coreutils timeout inside the box (killing nsenter from outside would leave
// the process running); the outer context is a backstop.
func execIn(id string, argv []string, stdin []byte, secs int, limit int) (*execResult, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(secs+15)*time.Second)
	defer cancel()
	args := append([]string{"run", id, "--", "timeout", "-k", "5", fmt.Sprint(secs)}, argv...)
	cmd := exec.CommandContext(ctx, "nixos-container", args...)
	cmd.Stdin = bytes.NewReader(stdin)
	so := &limitedBuffer{max: limit}
	se := &limitedBuffer{max: maxOutput}
	cmd.Stdout, cmd.Stderr = so, se
	cmd.WaitDelay = 5 * time.Second
	err := cmd.Run()
	res := &execResult{}
	if err != nil {
		var ee *exec.ExitError
		if !errors.As(err, &ee) {
			return nil, err
		}
		res.Exit = ee.ExitCode()
	}
	res.TimedOut = ctx.Err() != nil || res.Exit == 124 || res.Exit == 137
	res.Truncated = so.truncated || se.truncated
	res.stdout = so.buf.Bytes()
	res.Stdout = so.buf.String()
	res.Stderr = se.buf.String()
	return res, nil
}

// ---- HTTP ----

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func httpError(w http.ResponseWriter, status int, format string, args ...any) {
	writeJSON(w, status, map[string]string{"error": fmt.Sprintf(format, args...)})
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(io.LimitReader(r.Body, maxFile)).Decode(v); err != nil {
		httpError(w, 400, "bad JSON body: %v", err)
		return false
	}
	return true
}

// box looks up the container named in the URL.
func box(w http.ResponseWriter, r *http.Request) *Container {
	id := r.PathValue("id")
	var c *Container
	if idRe.MatchString(id) {
		c = readMeta(id)
	}
	if c == nil {
		httpError(w, 404, "no such container: %s", id)
	}
	return c
}

func running(w http.ResponseWriter, r *http.Request) *Container {
	c := box(w, r)
	if c != nil && c.State != "running" && c.State != "updating" {
		httpError(w, 409, "container is %s", c.State)
		return nil
	}
	return c
}

func handleCreate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Config  json.RawMessage `json:"config"`
		TTLSecs *int            `json:"ttl_secs"`
		Owner   string          `json:"owner"`
	}
	if !decode(w, r, &req) {
		return
	}
	bc, err := parseConfig(req.Config)
	if err != nil {
		httpError(w, 400, "%v", err)
		return
	}
	ttl := opt.defaultTTL
	if req.TTLSecs != nil {
		if *req.TTLSecs <= 0 {
			httpError(w, 400, "ttl_secs must be positive")
			return
		}
		ttl = *req.TTLSecs
	}
	mu.Lock()
	now := time.Now().UTC().Truncate(time.Second)
	c := &Container{
		ID:        newID(),
		State:     "creating",
		CreatedAt: now,
		ExpiresAt: now.Add(time.Duration(ttl) * time.Second),
		Owner:     req.Owner,
		Config:    req.Config,
	}
	err = writeMeta(c)
	mu.Unlock()
	if err != nil {
		httpError(w, 500, "write state: %v", err)
		return
	}
	log.Printf("%s: creating for %q, ttl %ds", c.ID, c.Owner, ttl)
	go createBox(c.ID, bc)
	writeJSON(w, 202, c)
}

func handleList(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]any{"containers": listMeta()})
}

func handleGet(w http.ResponseWriter, r *http.Request) {
	if c := box(w, r); c != nil {
		writeJSON(w, 200, c)
	}
}

func handleDelete(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !idRe.MatchString(id) {
		httpError(w, 404, "no such container: %s", id)
		return
	}
	destroy(id)
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func handleLog(w http.ResponseWriter, r *http.Request) {
	c := box(w, r)
	if c == nil {
		return
	}
	f, err := os.Open(filepath.Join(boxDir(c.ID), "build.log"))
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if err != nil {
		return
	}
	defer f.Close()
	if st, err := f.Stat(); err == nil && st.Size() > maxLog {
		_, _ = f.Seek(st.Size()-maxLog, io.SeekStart)
	}
	_, _ = io.Copy(w, f)
}

func handleReconfigure(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Config json.RawMessage `json:"config"`
	}
	if !decode(w, r, &req) {
		return
	}
	bc, err := parseConfig(req.Config)
	if err != nil {
		httpError(w, 400, "%v", err)
		return
	}
	id := r.PathValue("id")
	var c *Container
	conflict := ""
	if idRe.MatchString(id) {
		updateMeta(id, func(m *Container) {
			if m.State != "running" {
				conflict = m.State
			} else {
				m.State = "updating"
			}
			c = m
		})
	}
	if c == nil {
		httpError(w, 404, "no such container: %s", id)
		return
	}
	if conflict != "" {
		httpError(w, 409, "container is %s", conflict)
		return
	}
	go reconfigureBox(id, bc, req.Config)
	writeJSON(w, 202, c)
}

func handleExtend(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TTLSecs int `json:"ttl_secs"`
	}
	if !decode(w, r, &req) {
		return
	}
	if req.TTLSecs <= 0 {
		httpError(w, 400, "ttl_secs must be positive")
		return
	}
	id := r.PathValue("id")
	var c *Container
	if idRe.MatchString(id) {
		updateMeta(id, func(m *Container) {
			m.ExpiresAt = time.Now().UTC().Truncate(time.Second).Add(time.Duration(req.TTLSecs) * time.Second)
			c = m
		})
	}
	if c == nil {
		httpError(w, 404, "no such container: %s", id)
		return
	}
	writeJSON(w, 200, c)
}

func handleExec(w http.ResponseWriter, r *http.Request) {
	c := running(w, r)
	if c == nil {
		return
	}
	var req struct {
		Cmd         json.RawMessage `json:"cmd"`
		Stdin       string          `json:"stdin"`
		TimeoutSecs int             `json:"timeout_secs"`
	}
	if !decode(w, r, &req) {
		return
	}
	var argv []string
	var s string
	if json.Unmarshal(req.Cmd, &s) == nil && s != "" {
		argv = []string{"sh", "-c", s}
	} else if json.Unmarshal(req.Cmd, &argv) != nil || len(argv) == 0 {
		httpError(w, 400, "cmd must be a shell string or a non-empty argv list")
		return
	}
	secs := req.TimeoutSecs
	if secs <= 0 {
		secs = 60
	}
	if secs > maxExecSecs {
		secs = maxExecSecs
	}
	res, err := execIn(c.ID, argv, []byte(req.Stdin), secs, maxOutput)
	if err != nil {
		httpError(w, 500, "exec: %v", err)
		return
	}
	writeJSON(w, 200, res)
}

// File access goes through exec, so paths mean what they mean inside the box.
const readScript = `if [ -d "$1" ]; then find "$1" -mindepth 1 -maxdepth 1 -printf '%y %f\n'; exit 10; fi
[ -e "$1" ] || exit 3
exec cat -- "$1"`

const writeScript = `mkdir -p -- "$(dirname -- "$1")" && cat > "$1"`

func handleFileGet(w http.ResponseWriter, r *http.Request) {
	c := running(w, r)
	if c == nil {
		return
	}
	path := "/" + r.PathValue("path")
	res, err := execIn(c.ID, []string{"sh", "-c", readScript, "sh", path}, nil, 300, maxFile)
	if err != nil {
		httpError(w, 500, "read: %v", err)
		return
	}
	switch res.Exit {
	case 0:
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(res.stdout)
	case 10:
		entries := []map[string]string{}
		for _, line := range strings.Split(strings.TrimRight(res.Stdout, "\n"), "\n") {
			kind, name, ok := strings.Cut(line, " ")
			if !ok {
				continue
			}
			t := "file"
			if kind == "d" {
				t = "dir"
			}
			entries = append(entries, map[string]string{"name": name, "type": t})
		}
		writeJSON(w, 200, map[string]any{"entries": entries})
	case 3:
		httpError(w, 404, "no such file: %s", path)
	default:
		httpError(w, 500, "read %s: exit %d: %s", path, res.Exit, res.Stderr)
	}
}

func handleFilePut(w http.ResponseWriter, r *http.Request) {
	c := running(w, r)
	if c == nil {
		return
	}
	path := "/" + r.PathValue("path")
	body, err := io.ReadAll(io.LimitReader(r.Body, maxFile))
	if err != nil {
		httpError(w, 400, "read body: %v", err)
		return
	}
	res, err := execIn(c.ID, []string{"sh", "-c", writeScript, "sh", path}, body, 300, maxOutput)
	if err != nil {
		httpError(w, 500, "write: %v", err)
		return
	}
	if res.Exit != 0 {
		httpError(w, 500, "write %s: exit %d: %s", path, res.Exit, res.Stderr)
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func handleIndex(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintln(w, "throwaway-containers: POST /containers {config:{flake|nixos|system}, ttl_secs?, owner?}; "+
		"GET /containers[/<id>[/log]]; PUT /containers/<id>/config; POST /containers/<id>/exec|extend; "+
		"GET|PUT /containers/<id>/files/<path>; DELETE /containers/<id>")
}

func serve() {
	// Boxes whose build died with the previous process can't finish.
	for _, c := range listMeta() {
		switch c.State {
		case "creating":
			destroy(c.ID)
		case "updating":
			updateMeta(c.ID, func(m *Container) {
				msg := "service restarted during update"
				m.State, m.Error = "running", &msg
			})
		}
	}
	reap()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", handleIndex)
	mux.HandleFunc("POST /containers", handleCreate)
	mux.HandleFunc("GET /containers", handleList)
	mux.HandleFunc("GET /containers/{id}", handleGet)
	mux.HandleFunc("DELETE /containers/{id}", handleDelete)
	mux.HandleFunc("GET /containers/{id}/log", handleLog)
	mux.HandleFunc("PUT /containers/{id}/config", handleReconfigure)
	mux.HandleFunc("POST /containers/{id}/exec", handleExec)
	mux.HandleFunc("POST /containers/{id}/extend", handleExtend)
	mux.HandleFunc("GET /containers/{id}/files/{path...}", handleFileGet)
	mux.HandleFunc("PUT /containers/{id}/files/{path...}", handleFilePut)
	addr := fmt.Sprintf(":%d", opt.port)
	log.Printf("listening on %s (default ttl %ds)", addr, opt.defaultTTL)
	log.Fatal(http.ListenAndServe(addr, mux))
}
