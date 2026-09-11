// Package policy implements the persistent JSON policy store for
// stable identities, roles, per-app grants, and seed import markers.
package policy

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/surma/surm-auth/auth"
)

// CurrentVersion is the only supported runtime policy schema version.
const CurrentVersion = 1

// Roles.
const (
	RoleAdmin = "admin"
	RoleUser  = "user"
)

// BackupSuffix is appended to the policy file path for the previous
// committed generation.
const BackupSuffix = ".bak"

// Policy is the on-disk policy document.
type Policy struct {
	Version   int                `json:"version"`
	Users     map[string]*User   `json:"users"`
	Grants    map[string][]Grant `json:"grants"`
	Imports   Imports            `json:"imports"`
	UpdatedAt string             `json:"updated_at"`
	UpdatedBy string             `json:"updated_by"`
}

// User is one stable identity. The map key and identity is
// "<provider>:<id>"; username is mutable display data.
type User struct {
	Provider  string `json:"provider"`
	ID        string `json:"id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	FirstSeen string `json:"first_seen"`
	LastSeen  string `json:"last_seen"`
}

// Grant authorizes one stable identity on one logical app.
type Grant struct {
	Provider string `json:"provider"`
	ID       string `json:"id"`
	Username string `json:"username"`
}

// Imports holds one-time seed import markers.
type Imports struct {
	SeedApps map[string]bool `json:"seed_apps"`
}

// Admin identifies a Nix-owned bootstrap administrator.
type Admin struct {
	Provider string
	ID       string
}

func subjectKey(provider, id string) string {
	return provider + ":" + id
}

func nowString() string {
	return time.Now().UTC().Format(time.RFC3339)
}

// ErrUnavailable is returned when the store lost its valid policy copy
// after a failed reload. Callers must map it to 503.
var ErrUnavailable = errors.New("policy store unavailable")

// Store is the persistent policy store. All mutations serialize through
// one mutex and publish in-memory state only after a successful atomic
// commit.
type Store struct {
	mu      sync.Mutex
	path    string
	current *Policy
	managed map[string]bool // bootstrap-managed subjects

	available bool
}

// Open loads the policy file. A missing file initializes an empty,
// uncommitted policy. A corrupt file fails startup so an operator can
// inspect and restore it with approval.
func Open(path string) (*Store, error) {
	s := &Store{
		path:    path,
		managed: make(map[string]bool),
	}

	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		s.current = emptyPolicy()
		s.available = true
		return s, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read policy file: %w", err)
	}

	p, err := parse(data)
	if err != nil {
		return nil, fmt.Errorf("policy file %s is corrupt: %w", path, err)
	}

	s.current = p
	s.available = true
	return s, nil
}

func emptyPolicy() *Policy {
	return &Policy{
		Version: CurrentVersion,
		Users:   map[string]*User{},
		Grants:  map[string][]Grant{},
		Imports: Imports{SeedApps: map[string]bool{}},
	}
}

// parse strictly decodes the policy document. Unknown fields, trailing
// data, and unsupported versions are rejected.
func parse(data []byte) (*Policy, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()

	var p Policy
	if err := dec.Decode(&p); err != nil {
		return nil, fmt.Errorf("invalid policy document: %w", err)
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, fmt.Errorf("trailing data after policy object")
	}

	if p.Version != CurrentVersion {
		return nil, fmt.Errorf("unsupported policy version %d (expected %d)", p.Version, CurrentVersion)
	}
	if p.Users == nil || p.Grants == nil || p.Imports.SeedApps == nil {
		return nil, fmt.Errorf("policy users, grants, and imports must be present")
	}

	for key, u := range p.Users {
		if u == nil {
			return nil, fmt.Errorf("user %q is null", key)
		}
		if u.Provider == "" || u.ID == "" {
			return nil, fmt.Errorf("user %q lacks a stable identity", key)
		}
		if key != subjectKey(u.Provider, u.ID) {
			return nil, fmt.Errorf("user key %q does not match identity %q", key, subjectKey(u.Provider, u.ID))
		}
	}
	for app, grants := range p.Grants {
		for _, g := range grants {
			if g.Provider == "" || g.ID == "" {
				return nil, fmt.Errorf("grant on app %q lacks a stable identity", app)
			}
		}
	}

	return &p, nil
}

// Available reports whether the store currently holds a valid policy
// copy and can authorize or mutate.
func (s *Store) Available() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.available
}

// Snapshot returns a deep copy of the last committed policy.
func (s *Store) Snapshot() *Policy {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.current.clone()
}

// Reload re-reads the policy file. A failure after a good load retains
// the good snapshot and marks the store unavailable until a valid
// reload or restart succeeds.
func (s *Store) Reload() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			err = fmt.Errorf("policy file disappeared")
		} else {
			err = fmt.Errorf("failed to read policy file: %w", err)
		}
		s.available = false
		return err
	}

	p, err := parse(data)
	if err != nil {
		s.available = false
		return fmt.Errorf("policy file is corrupt: %w", err)
	}

	s.current = p
	s.available = true
	return nil
}

func (p *Policy) clone() *Policy {
	out := &Policy{
		Version:   p.Version,
		Users:     make(map[string]*User, len(p.Users)),
		Grants:    make(map[string][]Grant, len(p.Grants)),
		Imports:   Imports{SeedApps: make(map[string]bool, len(p.Imports.SeedApps))},
		UpdatedAt: p.UpdatedAt,
		UpdatedBy: p.UpdatedBy,
	}
	for k, u := range p.Users {
		copied := *u
		out.Users[k] = &copied
	}
	for k, grants := range p.Grants {
		out.Grants[k] = append([]Grant(nil), grants...)
	}
	for k, v := range p.Imports.SeedApps {
		out.Imports.SeedApps[k] = v
	}
	return out
}

// commit atomically writes the candidate and publishes it in memory.
// The caller must hold the store mutex. The previous committed file is
// kept as a .bak backup through an atomic write. A failed commit
// leaves the previous in-memory policy active.
func (s *Store) commit(candidate *Policy, by string) error {
	candidate.Version = CurrentVersion
	candidate.UpdatedAt = nowString()
	candidate.UpdatedBy = by

	data, err := json.MarshalIndent(candidate, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal policy: %w", err)
	}
	data = append(data, '\n')

	dir := filepath.Dir(s.path)

	// Back up the last good committed policy before replacing the
	// file. The backup comes from the validated in-memory snapshot,
	// never from the on-disk bytes: a file corrupted between a
	// successful load and this commit must not replace the last good
	// backup.
	prev, err := json.MarshalIndent(s.current, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal previous policy: %w", err)
	}
	prev = append(prev, '\n')
	if _, err := os.Stat(s.path); err == nil {
		if err := atomicWrite(dir, s.path+BackupSuffix, prev); err != nil {
			return fmt.Errorf("failed to back up policy: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("failed to inspect previous policy: %w", err)
	}

	if err := atomicWrite(dir, s.path, data); err != nil {
		return fmt.Errorf("failed to commit policy: %w", err)
	}

	s.current = candidate
	return nil
}

// atomicWrite writes data to a temporary file inside dir and renames
// it onto target, syncing file and directory.
func atomicWrite(dir, target string, data []byte) error {
	tmp, err := os.CreateTemp(dir, ".surm-auth-*.tmp")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer func() {
		tmp.Close()
		os.Remove(tmpPath)
	}()
	if err := tmp.Chmod(0600); err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		return err
	}
	if err := tmp.Sync(); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, target); err != nil {
		return err
	}
	if dirHandle, err := os.Open(dir); err == nil {
		dirHandle.Sync()
		dirHandle.Close()
	}
	return nil
}

// HasAccess reports whether the identity holds a grant on the app or
// the admin role.
func (s *Store) HasAccess(app, provider, id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return false, ErrUnavailable
	}

	for _, g := range s.current.Grants[app] {
		if g.Provider == provider && g.ID == id {
			return true, nil
		}
	}
	if u := s.current.Users[subjectKey(provider, id)]; u != nil && u.Role == RoleAdmin {
		return true, nil
	}
	return false, nil
}

// IsAdmin reports whether the identity holds the admin role.
func (s *Store) IsAdmin(provider, id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return false, ErrUnavailable
	}

	u := s.current.Users[subjectKey(provider, id)]
	return u != nil && u.Role == RoleAdmin, nil
}

// SeedImported reports whether the app's initial seed import completed.
func (s *Store) SeedImported(app string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.current.Imports.SeedApps[app]
}

// UpsertUser updates mutable display data for the identity without
// changing its role or grants. Unknown users are created with the
// default role.
func (s *Store) UpsertUser(user *auth.User, by string) error {
	if user == nil || user.Provider == "" || user.ID == "" {
		return fmt.Errorf("user requires a stable provider and ID")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return ErrUnavailable
	}

	candidate := s.current.clone()
	key := subjectKey(user.Provider, user.ID)
	now := nowString()
	if existing, ok := candidate.Users[key]; ok {
		if user.Username != "" {
			existing.Username = user.Username
		}
		existing.LastSeen = now
	} else {
		candidate.Users[key] = &User{
			Provider:  user.Provider,
			ID:        user.ID,
			Username:  user.Username,
			Role:      RoleUser,
			FirstSeen: now,
			LastSeen:  now,
		}
	}

	return s.commit(candidate, by)
}

// AddGrant grants the stable identity access to the app. Adding an
// existing grant is a no-op.
func (s *Store) AddGrant(app, provider, id, username, by string) error {
	if app == "" || provider == "" || id == "" {
		return fmt.Errorf("grant requires an app and a stable identity")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return ErrUnavailable
	}

	candidate := s.current.clone()
	for _, g := range candidate.Grants[app] {
		if g.Provider == provider && g.ID == id {
			return nil
		}
	}
	candidate.Grants[app] = append(candidate.Grants[app], Grant{
		Provider: provider,
		ID:       id,
		Username: username,
	})

	return s.commit(candidate, by)
}

// RemoveGrant removes one grant. Removing an absent grant is a no-op.
func (s *Store) RemoveGrant(app, provider, id, by string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return ErrUnavailable
	}

	candidate := s.current.clone()
	grants := candidate.Grants[app]
	kept := grants[:0:0]
	for _, g := range grants {
		if g.Provider == provider && g.ID == id {
			continue
		}
		kept = append(kept, g)
	}
	if len(kept) == len(grants) {
		return nil
	}
	if len(kept) == 0 {
		delete(candidate.Grants, app)
	} else {
		candidate.Grants[app] = kept
	}

	return s.commit(candidate, by)
}

// SetRole changes one mutable role. Bootstrap-managed admins and the
// last admin cannot be demoted.
func (s *Store) SetRole(provider, id, role, by string) error {
	if role != RoleAdmin && role != RoleUser {
		return fmt.Errorf("role must be %q or %q", RoleAdmin, RoleUser)
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return ErrUnavailable
	}

	key := subjectKey(provider, id)
	user, ok := s.current.Users[key]
	if !ok {
		return fmt.Errorf("unknown user %q", key)
	}
	if s.managed[key] && role != RoleAdmin {
		return fmt.Errorf("user %q is managed by Nix and cannot be demoted through the UI", key)
	}
	if user.Role == RoleAdmin && role != RoleAdmin && s.countAdminsLocked() <= 1 {
		return fmt.Errorf("cannot demote the last admin")
	}

	candidate := s.current.clone()
	candidate.Users[key].Role = role
	return s.commit(candidate, by)
}

func (s *Store) countAdminsLocked() int {
	count := 0
	for _, u := range s.current.Users {
		if u.Role == RoleAdmin {
			count++
		}
	}
	return count
}

// Bootstrap atomically commits bootstrap admin roles, initial seed
// grants, and seed import markers in one transaction. Seed users must
// already be resolved to stable identities; a resolution failure must
// prevent this call so no partial state is committed.
func (s *Store) Bootstrap(admins []Admin, seeds map[string][]*auth.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.available {
		return ErrUnavailable
	}

	candidate := s.current.clone()
	now := nowString()

	for _, admin := range admins {
		if admin.Provider == "" || admin.ID == "" {
			return fmt.Errorf("bootstrap admin requires a stable provider and ID")
		}
		key := subjectKey(admin.Provider, admin.ID)
		s.managed[key] = true
		if existing, ok := candidate.Users[key]; ok {
			existing.Role = RoleAdmin
			existing.LastSeen = now
		} else {
			candidate.Users[key] = &User{
				Provider:  admin.Provider,
				ID:        admin.ID,
				Role:      RoleAdmin,
				FirstSeen: now,
				LastSeen:  now,
			}
		}
	}

	for app, users := range seeds {
		for _, u := range users {
			if u == nil || u.Provider == "" || u.ID == "" {
				return fmt.Errorf("seed user on app %q lacks a stable identity", app)
			}
			exists := false
			for _, g := range candidate.Grants[app] {
				if g.Provider == u.Provider && g.ID == u.ID {
					exists = true
					break
				}
			}
			if !exists {
				candidate.Grants[app] = append(candidate.Grants[app], Grant{
					Provider: u.Provider,
					ID:       u.ID,
					Username: u.Username,
				})
			}
		}
		// Mark the import complete even for an empty seed set.
		candidate.Imports.SeedApps[app] = true
	}

	return s.commit(candidate, "bootstrap")
}

// IsManaged reports whether the subject is a Nix-owned bootstrap admin.
func (s *Store) IsManaged(provider, id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.managed[subjectKey(provider, id)]
}
