package policy

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/surma/surm-auth/auth"
)

func testUser(id, username, role string) *auth.User {
	return &auth.User{Provider: "github", ID: id, Username: username}
}

func adminSpec(id string) Admin {
	return Admin{Provider: "github", ID: id}
}

func openStore(t *testing.T) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "policy.json")
	s, err := Open(path)
	if err != nil {
		t.Fatalf("Open failed: %v", err)
	}
	return s, path
}

func writeRawPolicy(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestOpenMissingFileInitializesEmpty(t *testing.T) {
	s, _ := openStore(t)

	snapshot := s.Snapshot()
	if snapshot.Version != CurrentVersion {
		t.Errorf("version = %d", snapshot.Version)
	}
	if len(snapshot.Users) != 0 || len(snapshot.Grants) != 0 {
		t.Errorf("fresh policy not empty: %+v", snapshot)
	}
	if !s.Available() {
		t.Error("fresh store should be available")
	}
}

func TestOpenCorruptFailsStartup(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	writeRawPolicy(t, path, `{"version": 1, "users": {"github:1": },`)

	if _, err := Open(path); err == nil {
		t.Fatal("corrupt cold startup accepted")
	}
}

func TestOpenUnsupportedVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	writeRawPolicy(t, path, `{"version": 2, "users": {}, "grants": {}, "imports": {"seed_apps": {}}}`)

	if _, err := Open(path); err == nil {
		t.Fatal("unsupported policy version accepted")
	}
}

func TestOpenRejectsUnknownFields(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	writeRawPolicy(t, path, `{
		"version": 1,
		"users": {},
		"grants": {},
		"imports": {"seed_apps": {}},
		"extra_field": true
	}`)

	if _, err := Open(path); err == nil {
		t.Fatal("unknown top-level field accepted")
	}

	writeRawPolicy(t, path, `{
		"version": 1,
		"users": {"github:1": {"provider": "github", "id": "1", "username": "a", "role": "user", "first_seen": "x", "last_seen": "y", "hacker": 1}},
		"grants": {},
		"imports": {"seed_apps": {}}
	}`)
	if _, err := Open(path); err == nil {
		t.Fatal("unknown field inside user accepted")
	}
}

func TestOpenRejectsTrailingData(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	writeRawPolicy(t, path, `{"version": 1, "users": {}, "grants": {}, "imports": {"seed_apps": {}}} trailing`)

	if _, err := Open(path); err == nil {
		t.Fatal("trailing JSON accepted")
	}
}

func TestOpenRejectsMismatchedUserIdentity(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")
	writeRawPolicy(t, path, `{
		"version": 1,
		"users": {"github:99": {"provider": "github", "id": "1", "username": "a", "role": "user", "first_seen": "x", "last_seen": "y"}},
		"grants": {},
		"imports": {"seed_apps": {}}
	}`)
	if _, err := Open(path); err == nil {
		t.Fatal("user key that does not match its identity accepted")
	}
}

func TestAddGrantPersistsAndBacksUp(t *testing.T) {
	s, path := openStore(t)

	if err := s.AddGrant("app1", "github", "1", "alice", "tester"); err != nil {
		t.Fatalf("AddGrant failed: %v", err)
	}
	if err := s.AddGrant("app1", "github", "2", "bob", "tester"); err != nil {
		t.Fatalf("AddGrant failed: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var onDisk Policy
	if err := json.Unmarshal(data, &onDisk); err != nil {
		t.Fatalf("on-disk policy invalid: %v", err)
	}
	if len(onDisk.Grants["app1"]) != 2 {
		t.Errorf("on-disk grants = %d", len(onDisk.Grants["app1"]))
	}
	if onDisk.UpdatedBy != "tester" {
		t.Errorf("updated_by = %q", onDisk.UpdatedBy)
	}

	backup, err := os.ReadFile(path + BackupSuffix)
	if err != nil {
		t.Fatalf("backup missing: %v", err)
	}
	var bakPolicy Policy
	if err := json.Unmarshal(backup, &bakPolicy); err != nil {
		t.Fatalf("backup invalid: %v", err)
	}
	if len(bakPolicy.Grants["app1"]) != 1 {
		t.Errorf("backup should hold the previous generation, has %d grants", len(bakPolicy.Grants["app1"]))
	}

	ok, err := s.HasAccess("app1", "github", "1")
	if err != nil || !ok {
		t.Errorf("HasAccess = %v, %v", ok, err)
	}
	ok, _ = s.HasAccess("app1", "github", "999")
	if ok {
		t.Error("unknown identity has access")
	}
}

// TestCorruptFileNeverReplacesGoodBackup covers corruption between a
// successful load and a later mutation: the malformed on-disk bytes
// must never replace the last good .bak backup.
func TestCorruptFileNeverReplacesGoodBackup(t *testing.T) {
	s, path := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.AddGrant("app1", "github", "2", "bob", "a"); err != nil {
		t.Fatal(err)
	}

	// The backup after the second commit holds the previous good
	// generation with one grant.
	before, err := os.ReadFile(path + BackupSuffix)
	if err != nil {
		t.Fatalf("backup missing: %v", err)
	}
	previous, err := parse(before)
	if err != nil {
		t.Fatalf("backup invalid after second commit: %v", err)
	}
	if len(previous.Grants["app1"]) != 1 {
		t.Fatalf("backup holds %d grants, want the previous generation's 1", len(previous.Grants["app1"]))
	}

	// Corrupt the live file on disk while the store keeps its good
	// in-memory snapshot.
	writeRawPolicy(t, path, `{corrupt`)

	// A later mutation must not copy the malformed bytes over the
	// last good backup.
	if err := s.AddGrant("app1", "github", "3", "carol", "a"); err != nil {
		t.Fatalf("mutation after corruption failed: %v", err)
	}

	after, err := os.ReadFile(path + BackupSuffix)
	if err != nil {
		t.Fatalf("backup missing: %v", err)
	}
	bak, err := parse(after)
	if err != nil {
		t.Fatalf("backup no longer parses after a later mutation: %v", err)
	}
	if len(bak.Grants["app1"]) != 2 {
		t.Errorf("backup holds %d grants, want the last good generation's 2", len(bak.Grants["app1"]))
	}

	// The store stays available and serves the new generation.
	if !s.Available() {
		t.Error("store unavailable after committing over a corrupt file")
	}
	ok, err := s.HasAccess("app1", "github", "3")
	if err != nil || !ok {
		t.Errorf("new grant lost: %v, %v", ok, err)
	}
}

func TestAddGrantIdempotent(t *testing.T) {
	s, _ := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatalf("re-adding a grant failed: %v", err)
	}
	snapshot := s.Snapshot()
	if len(snapshot.Grants["app1"]) != 1 {
		t.Errorf("duplicate grant appended: %d", len(snapshot.Grants["app1"]))
	}
}

func TestRemoveGrant(t *testing.T) {
	s, _ := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.RemoveGrant("app1", "github", "1", "a"); err != nil {
		t.Fatalf("RemoveGrant failed: %v", err)
	}
	ok, _ := s.HasAccess("app1", "github", "1")
	if ok {
		t.Error("removed grant still authorizes")
	}
	// Removing an absent grant is a no-op.
	if err := s.RemoveGrant("app1", "github", "1", "a"); err != nil {
		t.Errorf("removing absent grant failed: %v", err)
	}
}

func TestFailedCommitKeepsPreviousMemoryState(t *testing.T) {
	s, path := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}

	// Make the state directory read-only so the next commit fails.
	dir := filepath.Dir(path)
	if err := os.Chmod(dir, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0700) })

	if err := s.AddGrant("app2", "github", "2", "bob", "a"); err == nil {
		t.Fatal("commit succeeded on a read-only directory")
	}

	// The previous committed policy must remain active.
	ok, err := s.HasAccess("app1", "github", "1")
	if err != nil || !ok {
		t.Errorf("previous grant lost after failed commit: %v, %v", ok, err)
	}
	ok, _ = s.HasAccess("app2", "github", "2")
	if ok {
		t.Error("uncommitted grant visible after failed commit")
	}
}

func TestBootstrapAndSeedMarkers(t *testing.T) {
	s, _ := openStore(t)

	admins := []Admin{adminSpec("1")}
	seeds := map[string][]*auth.User{
		"hedgedoc2": {testUser("1", "surma", "")},
		"brain":     {}, // Empty seed set must also be marked imported.
	}
	if err := s.Bootstrap(admins, seeds); err != nil {
		t.Fatalf("Bootstrap failed: %v", err)
	}

	if !s.SeedImported("hedgedoc2") || !s.SeedImported("brain") {
		t.Error("seed markers missing after bootstrap")
	}

	snapshot := s.Snapshot()
	if len(snapshot.Grants["hedgedoc2"]) != 1 {
		t.Errorf("seed grants = %d", len(snapshot.Grants["hedgedoc2"]))
	}
	if len(snapshot.Grants["brain"]) != 0 {
		t.Errorf("empty seed set created grants: %d", len(snapshot.Grants["brain"]))
	}

	admin, ok := snapshot.Users["github:1"]
	if !ok || admin.Role != RoleAdmin {
		t.Errorf("bootstrap admin not committed: %+v", admin)
	}

	// Removing the final grant must not remove the import marker.
	if err := s.RemoveGrant("hedgedoc2", "github", "1", "a"); err != nil {
		t.Fatal(err)
	}
	if !s.SeedImported("hedgedoc2") {
		t.Error("import marker lost after final-grant removal")
	}
}

func TestSeedMarkerSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")

	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Bootstrap(nil, map[string][]*auth.User{"app1": {testUser("7", "seven", "")}}); err != nil {
		t.Fatal(err)
	}

	// Simulate an admin removing every grant, then a restart.
	if err := s.RemoveGrant("app1", "github", "7", "a"); err != nil {
		t.Fatal(err)
	}

	reopened, err := Open(path)
	if err != nil {
		t.Fatalf("restart failed: %v", err)
	}
	if reopened.SeedImported("app1") != true {
		t.Error("restart lost the import marker")
	}
	reopened2, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(reopened2.Snapshot().Grants) != 0 || len(reopened2.Snapshot().Grants["app1"]) != 0 {
		t.Error("restart re-imported seeds")
	}
}

// failingDirHandle stands in for an open directory whose Sync fails.
// The failure models an I/O error on the final durability step after
// a successful rename.
type failingDirHandle struct {
	syncErr error
}

func (h failingDirHandle) Sync() error  { return h.syncErr }
func (h failingDirHandle) Close() error { return nil }

// TestDirSyncFailureAfterRenameKeepsPreviousPolicy covers the final
// directory durability step of a commit: the rename succeeds, then the
// directory sync fails. The commit must report the failure, the store
// must keep the previous in-memory policy, and the last good backup
// must survive.
func TestDirSyncFailureAfterRenameKeepsPreviousPolicy(t *testing.T) {
	s, path := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}

	// The backup's durability step still succeeds; only the live
	// file's post-rename directory sync fails.
	calls := 0
	s.dirOpener = func(dir string) (dirHandle, error) {
		calls++
		if calls == 1 {
			return os.Open(dir)
		}
		return failingDirHandle{syncErr: errors.New("injected sync failure")}, nil
	}

	if err := s.AddGrant("app2", "github", "2", "bob", "a"); err == nil {
		t.Fatal("commit succeeded despite a failed directory sync")
	}
	if calls != 2 {
		t.Fatalf("directory syncs = %d, want 2 (backup, then live file)", calls)
	}

	// The previous in-memory policy stays active and available.
	if !s.Available() {
		t.Error("store became unavailable after a failed directory sync")
	}
	ok, err := s.HasAccess("app1", "github", "1")
	if err != nil || !ok {
		t.Errorf("previous grant lost after failed directory sync: %v, %v", ok, err)
	}
	ok, _ = s.HasAccess("app2", "github", "2")
	if ok {
		t.Error("uncommitted grant visible after failed directory sync")
	}

	// The backup still holds the last good generation.
	backup, err := os.ReadFile(path + BackupSuffix)
	if err != nil {
		t.Fatalf("backup missing: %v", err)
	}
	bak, err := parse(backup)
	if err != nil {
		t.Fatalf("backup invalid after failed commit: %v", err)
	}
	if len(bak.Grants["app1"]) != 1 || len(bak.Grants["app2"]) != 0 {
		t.Errorf("backup no longer holds the previous generation: %+v", bak.Grants)
	}
}

// TestDirOpenFailureKeepsPreviousPolicy covers the other half of the
// durability step: the directory cannot be opened for sync at all.
// The failure must propagate instead of reporting success.
func TestDirOpenFailureKeepsPreviousPolicy(t *testing.T) {
	s, _ := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}

	s.dirOpener = func(dir string) (dirHandle, error) {
		return nil, errors.New("injected open failure")
	}

	if err := s.AddGrant("app2", "github", "2", "bob", "a"); err == nil {
		t.Fatal("commit succeeded despite a failed directory open")
	}

	if !s.Available() {
		t.Error("store became unavailable after a failed directory open")
	}
	ok, err := s.HasAccess("app1", "github", "1")
	if err != nil || !ok {
		t.Errorf("previous grant lost after failed directory open: %v, %v", ok, err)
	}
	ok, _ = s.HasAccess("app2", "github", "2")
	if ok {
		t.Error("uncommitted grant visible after failed directory open")
	}
}

func TestBootstrapAdminReassertAndGuard(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")

	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Bootstrap([]Admin{adminSpec("1")}, nil); err != nil {
		t.Fatal(err)
	}

	// Bootstrap-managed admins cannot be demoted through the UI.
	if err := s.SetRole("github", "1", RoleUser, "attacker"); err == nil {
		t.Fatal("bootstrap admin demoted through the UI")
	}
	if ok, _ := s.IsAdmin("github", "1"); !ok {
		t.Error("bootstrap admin lost the admin role")
	}
	if !s.IsManaged("github", "1") {
		t.Error("bootstrap admin not flagged as managed")
	}

	// The guard blocks every UI demotion, so simulate a foreign edit
	// on disk that strips the role, then load it.
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	demoted := replaceOnce(t, string(raw), `"role": "admin"`, `"role": "user"`)
	writeRawPolicy(t, path, demoted)
	if err := s.Reload(); err != nil {
		t.Fatal(err)
	}
	if ok, _ := s.IsAdmin("github", "1"); ok {
		t.Fatal("demoted role did not load; the reassertion below would prove nothing")
	}

	// Startup reasserts the bootstrap admin role.
	if err := s.Bootstrap([]Admin{adminSpec("1")}, nil); err != nil {
		t.Fatal(err)
	}
	if ok, _ := s.IsAdmin("github", "1"); !ok {
		t.Error("startup failed to reassert the bootstrap admin role")
	}
	if !s.IsManaged("github", "1") {
		t.Error("reassertion lost the managed flag")
	}

	// The reassertion was persisted and survives a restart.
	reopened, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if ok, _ := reopened.IsAdmin("github", "1"); !ok {
		t.Error("reasserted admin role not persisted across restart")
	}
}

func TestLastAdminGuard(t *testing.T) {
	s2, _ := openStore(t)
	if err := s2.UpsertUser(testUser("1", "a", ""), "a"); err != nil {
		t.Fatal(err)
	}
	if err := s2.UpsertUser(testUser("2", "b", ""), "b"); err != nil {
		t.Fatal(err)
	}
	if err := s2.SetRole("github", "1", RoleAdmin, "a"); err != nil {
		t.Fatal(err)
	}
	if err := s2.SetRole("github", "2", RoleAdmin, "b"); err != nil {
		t.Fatal(err)
	}

	// Concurrent demotions of the final admin: exactly one may fail.
	var wg sync.WaitGroup
	errCh := make(chan error, 2)
	for _, id := range []string{"1", "2"} {
		id := id
		wg.Add(1)
		go func() {
			defer wg.Done()
			errCh <- s2.SetRole("github", id, RoleUser, "x")
		}()
	}
	wg.Wait()
	close(errCh)

	failures := 0
	for err := range errCh {
		if err != nil {
			failures++
		}
	}
	if failures == 0 {
		t.Fatal("all admins were demoted; last-admin guard failed")
	}
	if failures > 1 {
		t.Fatalf("unexpected number of failures: %d", failures)
	}
	if admins := countAdmins(s2.Snapshot()); admins != 1 {
		t.Errorf("admin count = %d, want 1", admins)
	}
}

func TestLastSingleAdminGuard(t *testing.T) {
	s, _ := openStore(t)
	if err := s.UpsertUser(testUser("1", "a", ""), "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRole("github", "1", RoleAdmin, "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRole("github", "1", RoleUser, "a"); err == nil {
		t.Fatal("the single admin was demoted")
	}
}

func TestSetRoleValidation(t *testing.T) {
	s, _ := openStore(t)
	if err := s.UpsertUser(testUser("1", "a", ""), "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRole("github", "1", "superadmin", "a"); err == nil {
		t.Fatal("invalid role accepted")
	}
	if err := s.SetRole("github", "404", RoleAdmin, "a"); err == nil {
		t.Fatal("role change for unknown user accepted")
	}
}

func TestUpsertUserPreservesRole(t *testing.T) {
	s, _ := openStore(t)
	if err := s.UpsertUser(testUser("1", "alice", ""), "a"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRole("github", "1", RoleAdmin, "a"); err != nil {
		t.Fatal(err)
	}

	renamed := &auth.User{Provider: "github", ID: "1", Username: "alice-renamed", Email: "x"}
	if err := s.UpsertUser(renamed, "a"); err != nil {
		t.Fatal(err)
	}

	snapshot := s.Snapshot()
	user := snapshot.Users["github:1"]
	if user.Username != "alice-renamed" {
		t.Errorf("username not updated: %q", user.Username)
	}
	if user.Role != RoleAdmin {
		t.Errorf("upsert changed the role: %q", user.Role)
	}
	// A username rename must preserve grants.
	if err := s.AddGrant("app1", "github", "1", "alice-renamed", "a"); err != nil {
		t.Fatal(err)
	}
	ok, _ := s.HasAccess("app1", "github", "1")
	if !ok {
		t.Error("grant lost")
	}
}

func TestReloadCorruptRetainsGoodSnapshot(t *testing.T) {
	s, path := openStore(t)
	if err := s.AddGrant("app1", "github", "1", "alice", "a"); err != nil {
		t.Fatal(err)
	}

	writeRawPolicy(t, path, `{corrupt`)
	if err := s.Reload(); err == nil {
		t.Fatal("corrupt reload succeeded")
	}
	if s.Available() {
		t.Error("store still available after corrupt reload")
	}

	// The good snapshot is retained for diagnostics.
	ok, err := s.HasAccess("app1", "github", "1")
	if err == nil || ok {
		t.Errorf("authorization served while unavailable: %v, %v", ok, err)
	}
	if !errors.Is(err, ErrUnavailable) {
		t.Errorf("error = %v, want ErrUnavailable", err)
	}

	// A valid reload restores availability.
	if err := s.AddGrant("app2", "github", "2", "bob", "a"); err == nil {
		t.Error("mutation accepted while unavailable")
	}
	writeRawPolicy(t, path, `{"version": 1, "users": {}, "grants": {}, "imports": {"seed_apps": {}}}`)
	if err := s.Reload(); err != nil {
		t.Fatalf("valid reload failed: %v", err)
	}
	if !s.Available() {
		t.Error("store not available after valid reload")
	}
}

func TestPolicyRoundtripOnDisk(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "policy.json")

	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Bootstrap([]Admin{adminSpec("42")}, map[string][]*auth.User{
		"app1": {testUser("1", "alice", "")},
	}); err != nil {
		t.Fatal(err)
	}

	reopened, err := Open(path)
	if err != nil {
		t.Fatalf("reload failed: %v", err)
	}
	ok, _ := reopened.HasAccess("app1", "github", "1")
	if !ok {
		t.Error("grant lost across restart")
	}
	admin, _ := reopened.IsAdmin("github", "42")
	if !admin {
		t.Error("bootstrap admin lost across restart")
	}
}

func TestConcurrentMutationsAreRaceFree(t *testing.T) {
	s, _ := openStore(t)
	if err := s.UpsertUser(testUser("1", "a", ""), "a"); err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			app := fmt.Sprintf("app%d", i%3)
			_ = s.AddGrant(app, "github", "1", "a", "a")
			_, _ = s.HasAccess(app, "github", "1")
			_ = s.Snapshot()
			_, _ = s.IsAdmin("github", "1")
		}(i)
	}
	wg.Wait()
}

func countAdmins(p *Policy) int {
	count := 0
	for _, u := range p.Users {
		if u.Role == RoleAdmin {
			count++
		}
	}
	return count
}

func replaceOnce(t *testing.T, s, old, new string) string {
	t.Helper()
	i := indexOf(s, old)
	if i < 0 {
		t.Fatalf("substring %q not found", old)
	}
	return s[:i] + new + s[i+len(old):]
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
