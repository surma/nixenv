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
- For NixOS config changes on this machine, edit the flake repo config (not /etc/nixos).

## Patterns That Work
- For Nu, use `".git" | path exists` (no positional arg) and `get -o` instead of deprecated `get -i`.

## Patterns That Don't Work
- Using `autoPatchelfHook` (or stdenv's automatic patchELF / strip fixups) on the claude-code GCS binary: patchelf reorganises the ELF and silently truncates the 122 MB Bun standalone payload, leaving only a bare bun runtime (102 MB) that prints bun's own help. Fix: explicit `patchelf --set-interpreter` only, with `dontPatchELF = true` and `dontStrip = true`.

## Known Issues / Gotchas
- navidrome containers use `nixpkgs = pkgs.path` (stable, nixos-25.11) for the NixOS module system, but the **package** comes from `pkgs-unstable`. The stable module has `MemoryDenyWriteExecute = true`, but navidrome 0.60.0 requires `false` (Taglib WASM JIT). Without the override, cover art extraction hangs, and the API returns 429 "Timed out while waiting for a pending request to complete". Fix: `systemd.services.navidrome.serviceConfig.MemoryDenyWriteExecute = lib.mkForce false` in the container config.
- nixpkgs-unstable rev `2fc6539b` (lastModified 1771848320) has a broken navidrome build: `invalid flag in pkg-config --cflags: --define-prefix`. Previous working rev: `0182a361` (lastModified 1771369470, narHash `sha256-0NBlEBKkN3lufyvFegY4TYv5mCNHbi5OmBDrzihbBMQ=`).

## Domain Notes
- The NixOS `services.qbittorrent` module uses a `systemd-tmpfiles` `L+` rule to forcibly symlink `qBittorrent.conf` → a read-only Nix store file on every container start and `nixos-rebuild switch`. Any settings not in `serverConfig` are wiped on restart. Always declare persistent qBittorrent settings (seeding limits, etc.) in `serverConfig`; never rely on in-UI changes surviving a restart.
- Plan mode extension (`modules/programs/pi/extensions/plan-mode/claude-plan-mode.ts`) queues `/plan accept` via `pi.sendUserMessage`, but sendUserMessage bypasses command handling, so the command never runs and `ctx.newSession()` is not triggered. This explains context not clearing after plan acceptance.
- `nix-update --flake` uses `nix-instantiate` + `builtins.getFlake` and fails if `.git` contains `fsmonitor--daemon.ipc` sockets (including in `.git/worktrees`). Remove those sockets before running.
- Zellij defaults to Nushell in this repo; set `GPG_TTY` in Nushell's `env.nu` (use `do -i { ^tty | str trim }`) to keep pinentry on the correct pane TTY.
- `packages/claude-code/default.nix` uses the GCS binary (same source as Homebrew). On Linux: explicit `patchelf --set-interpreter` only, with `dontPatchELF = true` and `dontStrip = true` to protect the Bun standalone payload.
