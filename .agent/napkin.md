# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-11 | self | Started work before reading .agent/napkin.md, violating the napkin skill's first-step requirement. | Read .agent/napkin.md before any other action at session start. |
| 2026-02-11 | self | Started multi-step work without creating a todo list as required by the pi-superpowers skill. | Create a todo list before multi-step changes to track progress. |
| 2026-02-07 | self | Changed only the cancellation message instead of aligning the cancel path with the same rejection handler as the "No" selection. | When asked to unify behaviors, share the exact helper path (state updates + response) so both cases are truly identical. |
| 2026-02-16 | self | update-all cleaned fsmonitor socket before `nix flake update`, but flake update recreated it and nix-update failed. | Remove fsmonitor socket after `nix flake update` (before nix-update runs). |
| 2026-02-16 | self | Assumed nix-update could auto-fetch versions for non-supported sources (hyperkey, claude-code). | For non-supported URLs, compute latest version in update-all and pass `--version` explicitly. |

## User Preferences
- Prefer simple solutions; assume no worktrees for this repo when cleaning fsmonitor sockets (use direct rm rather than find).
- When running update-all, disable git fsmonitor for the duration instead of relying solely on repeated socket deletions.

## Patterns That Work
- For Nu, use `".git" | path exists` (no positional arg) and `get -o` instead of deprecated `get -i`.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- Plan mode extension (`modules/programs/pi/extensions/plan-mode/claude-plan-mode.ts`) queues `/plan accept` via `pi.sendUserMessage`, but sendUserMessage bypasses command handling, so the command never runs and `ctx.newSession()` is not triggered. This explains context not clearing after plan acceptance.
- `nix-update --flake` uses `nix-instantiate` + `builtins.getFlake` and fails if `.git` contains `fsmonitor--daemon.ipc` sockets (including in `.git/worktrees`). Remove those sockets before running.
- Zellij defaults to Nushell in this repo; set `GPG_TTY` in Nushell's `env.nu` (use `do -i { ^tty | str trim }`) to keep pinentry on the correct pane TTY.
