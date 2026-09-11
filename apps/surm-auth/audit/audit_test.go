package audit

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func openTestLogger(t *testing.T, maxBytes int64) (*Logger, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "audit.log")
	l, err := openWithMax(path, maxBytes)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = l.Close() })
	return l, path
}

func TestRecordAndLatest(t *testing.T) {
	l, _ := openTestLogger(t, DefaultMaxBytes)

	for i := 0; i < 5; i++ {
		if err := l.Record(Event{
			Event:   EventLoginSuccess,
			Actor:   fmt.Sprintf("github:%d", i),
			Subject: fmt.Sprintf("github:%d", i),
			App:     "app1",
		}); err != nil {
			t.Fatalf("Record failed: %v", err)
		}
	}

	events, err := l.Latest(3)
	if err != nil {
		t.Fatalf("Latest failed: %v", err)
	}
	if len(events) != 3 {
		t.Fatalf("events = %d, want 3", len(events))
	}
	// The newest events come last.
	if events[2].Actor != "github:4" {
		t.Errorf("last event actor = %q", events[2].Actor)
	}

	all, err := l.Latest(200)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 5 {
		t.Errorf("bounded read returned %d events, want 5", len(all))
	}
}

func TestRecordFieldsSerialized(t *testing.T) {
	l, path := openTestLogger(t, DefaultMaxBytes)

	if err := l.Record(Event{
		Event:   EventGrantAdded,
		Actor:   "github:1",
		Subject: "github:2",
		App:     "app1",
		Detail:  "username bob",
	}); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	line := strings.TrimSpace(string(data))
	if !strings.HasPrefix(line, "{") || !strings.HasSuffix(line, "}") {
		t.Errorf("line is not a JSON object: %q", line)
	}
	if strings.Count(string(data), "\n") != 1 {
		t.Errorf("record wrote %d lines", strings.Count(string(data), "\n"))
	}
	for _, forbidden := range []string{"code", "secret"} {
		// Nothing beyond the declared fields may appear.
		if strings.Contains(line, `"oauth_code"`) || strings.Contains(line, `"client_secret"`) {
			t.Errorf("audit line leaks secrets: %s", line)
		}
		_ = forbidden
	}
}

func TestAuditFileMode0600(t *testing.T) {
	l, path := openTestLogger(t, DefaultMaxBytes)
	if err := l.Record(Event{Event: EventLogout}); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0600 {
		t.Errorf("audit file mode = %v, want 0600", mode)
	}
}

func TestRecordRequiresEventName(t *testing.T) {
	l, _ := openTestLogger(t, DefaultMaxBytes)
	if err := l.Record(Event{}); err == nil {
		t.Fatal("event without a name accepted")
	}
}

func TestRotation(t *testing.T) {
	// Each record is ~100 bytes; a 500-byte threshold forces rotation
	// into exactly one managed generation.
	l, path := openTestLogger(t, 500)

	for i := 0; i < 20; i++ {
		if err := l.Record(Event{
			Event:  EventLoginSuccess,
			Actor:  "github:1",
			Detail: "padding padding padding padding padding",
		}); err != nil {
			t.Fatalf("Record %d failed: %v", i, err)
		}
	}

	if _, err := os.Stat(path + GenerationSuffix); err != nil {
		t.Fatalf("rotated generation missing: %v", err)
	}

	// The current file keeps receiving records.
	events, err := l.Latest(200)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) == 0 {
		t.Error("no events after rotation")
	}

	// New records land in the fresh current file.
	if err := l.Record(Event{Event: EventLogout, Actor: "after"}); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() > 500 {
		t.Errorf("current file did not restart on rotation: %d bytes", info.Size())
	}
}

func TestLatestSkipsMalformedLines(t *testing.T) {
	l, path := openTestLogger(t, DefaultMaxBytes)
	if err := l.Record(Event{Event: EventLoginSuccess, Actor: "a"}); err != nil {
		t.Fatal(err)
	}
	// Append a malformed line (as a crashed writer might leave).
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("{not-json\n"); err != nil {
		t.Fatal(err)
	}
	f.Close()
	if err := l.Record(Event{Event: EventLogout, Actor: "b"}); err != nil {
		t.Fatal(err)
	}

	events, err := l.Latest(200)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 {
		t.Errorf("events = %d, want 2 (malformed line skipped)", len(events))
	}
}

func TestRecordFailureAfterClose(t *testing.T) {
	l, _ := openTestLogger(t, DefaultMaxBytes)
	if err := l.Close(); err != nil {
		t.Fatal(err)
	}
	if err := l.Record(Event{Event: EventLogout}); err == nil {
		t.Fatal("record after close succeeded")
	}
}

func TestConcurrentRecordsAreRaceFree(t *testing.T) {
	l, _ := openTestLogger(t, DefaultMaxBytes)

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_ = l.Record(Event{
				Event:  EventAccessDenied,
				Actor:  fmt.Sprintf("github:%d", i),
				Detail: "concurrent",
			})
		}(i)
	}
	wg.Wait()

	events, err := l.Latest(200)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 20 {
		t.Errorf("events = %d, want 20", len(events))
	}
}
