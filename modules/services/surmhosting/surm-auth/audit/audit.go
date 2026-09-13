// Package audit implements the JSON Lines audit log with serialized
// appends, size rotation, and bounded reads.
package audit

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// DefaultMaxBytes is the rotation threshold (10 MiB).
const DefaultMaxBytes int64 = 10 << 20

// GenerationSuffix is the explicitly managed rotated generation.
const GenerationSuffix = ".1"

// Event names recorded in the audit log.
const (
	EventLoginSuccess     = "login_success"
	EventLoginDenied      = "login_denied"
	EventAccessDenied     = "access_denied"
	EventGrantAdded       = "grant_added"
	EventGrantRemoved     = "grant_removed"
	EventRoleChanged      = "role_changed"
	EventLogout           = "logout"
	EventSeedImport       = "seed_import"
	EventPolicyWriteError = "policy_write_error"
)

// Event is one audit record.
type Event struct {
	Time    string `json:"time"`
	Event   string `json:"event"`
	Actor   string `json:"actor,omitempty"`
	Subject string `json:"subject,omitempty"`
	App     string `json:"app,omitempty"`
	Detail  string `json:"detail,omitempty"`
}

// Logger appends audit events to a JSON Lines file.
type Logger struct {
	mu       sync.Mutex
	path     string
	maxBytes int64
	file     *os.File
	size     int64
}

// Open opens or creates the audit log with mode 0600.
func Open(path string) (*Logger, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, fmt.Errorf("failed to create audit directory: %w", err)
	}
	return openWithMax(path, DefaultMaxBytes)
}

func openWithMax(path string, maxBytes int64) (*Logger, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return nil, fmt.Errorf("failed to open audit log: %w", err)
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, fmt.Errorf("failed to stat audit log: %w", err)
	}
	return &Logger{
		path:     path,
		maxBytes: maxBytes,
		file:     file,
		size:     info.Size(),
	}, nil
}

// Record appends one event. Appends serialize through the logger
// mutex, and the log rotates into one managed generation at the size
// threshold.
func (l *Logger) Record(event Event) error {
	if event.Time == "" {
		event.Time = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if event.Event == "" {
		return fmt.Errorf("audit event name must not be empty")
	}

	line, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal audit event: %w", err)
	}
	line = append(line, '\n')

	l.mu.Lock()
	defer l.mu.Unlock()

	if l.file == nil {
		return fmt.Errorf("audit log is closed")
	}
	if l.size+int64(len(line)) > l.maxBytes {
		if err := l.rotateLocked(); err != nil {
			return fmt.Errorf("failed to rotate audit log: %w", err)
		}
	}
	n, err := l.file.Write(line)
	l.size += int64(n)
	if err != nil {
		return fmt.Errorf("failed to append audit event: %w", err)
	}
	return nil
}

func (l *Logger) rotateLocked() error {
	l.file.Close()
	l.file = nil
	if err := os.Rename(l.path, l.path+GenerationSuffix); err != nil && !os.IsNotExist(err) {
		return err
	}
	file, err := os.OpenFile(l.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	l.file = file
	l.size = 0
	return nil
}

// Latest returns the most recent n events from the current generation.
// Malformed lines are skipped.
func (l *Logger) Latest(n int) ([]Event, error) {
	if n <= 0 {
		return nil, nil
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	data, err := os.ReadFile(l.path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read audit log: %w", err)
	}

	events := make([]Event, 0, n)
	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		var event Event
		if err := json.Unmarshal(line, &event); err != nil {
			continue
		}
		events = append(events, event)
	}

	if len(events) > n {
		events = events[len(events)-n:]
	}
	// Return newest last for chronological reading.
	return events, nil
}

// Close closes the underlying file.
func (l *Logger) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file == nil {
		return nil
	}
	err := l.file.Close()
	l.file = nil
	return err
}
