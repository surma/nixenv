# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-03-06 | self | Loaded skill files before reading `.agent/napkin.md`, violating the napkin first-step rule. | Always read `.agent/napkin.md` immediately at session start before any other tool call. |
| 2026-03-06 | self | Used `cat` in a bash command to inspect `/etc/resolv.conf`, violating the rule to use the `read` tool for file contents. | Always use the `read` tool for file content inspection; reserve `bash` for process/status commands. |
| 2026-03-06 | self | Trusted a doc pointer (`templates/agent-first/steps.md`) without checking the filesystem and hit an avoidable ENOENT. | When docs reference helper files, verify with `find` first and pivot to actual source files before continuing. |
| 2026-03-06 | self | Enabled `nix-openclaw` module on scout without applying `inputs.nix-openclaw.overlays.default`, causing `attribute 'openclaw' missing` during HM eval. | Whenever importing `nix-openclaw.homeManagerModules.openclaw`, also set `nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ]`. |
| 2026-03-06 | self | Initially put `gateway.auth.token` inline in Nix config, which would leak a secret into the store. | For gateway auth, decrypt to an `EnvironmentFile` (`OPENCLAW_GATEWAY_TOKEN=...`) and set `gateway.auth.mode = "token"` instead of embedding secrets in Nix values. |
| 2026-03-06 | self | Tried to use `jq` for API-response inspection on this host; it is not installed and caused avoidable command failure. | Use a short Python JSON parser for ad-hoc API payload inspection unless `jq` is confirmed present. |
| 2026-03-06 | self | Tried `nixos-container run` from an unprivileged shell and lost time on `nsenter ... Permission denied`. | Check privilege constraints early; for live container introspection on nexus, either run with root access or ask user for command outputs. |
| 2026-03-06 | self | Used `sed` in a shell command to trim `git show` output instead of sticking to `read`/direct tool outputs. | Avoid `cat`/`sed` for viewing file content; use `read` for files and plain `git`/tool output filtering when needed. |
| 2026-03-06 | self | Ran `cargo test` in dump repo without OpenSSL/pkg-config env and misread the first red run as useful test evidence. | For dump repo tests on this host, set `OPENSSL_LIB_DIR=$(nix eval --raw nixpkgs#openssl.out)/lib`, `OPENSSL_INCLUDE_DIR=$(nix eval --raw nixpkgs#openssl.dev)/include`, and run via `nix shell nixpkgs#pkg-config -c cargo test ...` before evaluating test outcomes. |
| 2026-03-06 | self | Appended test modules, then accidentally removed them in later broad replacements and almost lost coverage. | After each structural edit, re-read file tail and re-run targeted tests to confirm newly added tests still exist and execute. |
| 2026-03-06 | self | Tried passing multiple test-name filters to `cargo test` as separate positional args and got “unexpected argument” failures. | Use one filter per `cargo test` invocation (or a shared prefix filter), run separate commands for multiple exact tests. |
| 2026-02-11 | self | Started work before reading .agent/napkin.md, violating the napkin skill's first-step requirement. | Read .agent/napkin.md before any other action at session start. |
| 2026-02-11 | self | Started multi-step work without creating a todo list as required by the pi-superpowers skill. | Create a todo list before multi-step changes to track progress. |
| 2026-02-07 | self | Changed only the cancellation message instead of aligning the cancel path with the same rejection handler as the "No" selection. | When asked to unify behaviors, share the exact helper path (state updates + response) so both cases are truly identical. |
| 2026-02-16 | self | update-all cleaned fsmonitor socket before `nix flake update`, but flake update recreated it and nix-update failed. | Remove fsmonitor socket after `nix flake update` (before nix-update runs). |
| 2026-03-05 | self | Added local flake input as `path:../sl2`; lock update failed in pure eval with forbidden absolute store path | For local-repo flake inputs in this setup, use `git+file:///absolute/path` instead of relative `path:` URLs |
| 2026-03-05 | self | Tried to automate interactive Helix repro with `script` and stalled instead of asking the user for direct command output sooner. | For interactive editor verification, request user-run commands immediately and continue from their output. |
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
- surmhosting containers (`container@lc-*`) copy host `/etc/resolv.conf` once at container start (`cp --remove-destination /etc/resolv.conf "$root/etc/resolv.conf"`). If they start at `network.target` before DNS providers populate host resolvconf (NetworkManager/tailscale), containers keep a stale/empty resolver config until restart.

## Domain Notes
- The NixOS `services.qbittorrent` module uses a `systemd-tmpfiles` `L+` rule to forcibly symlink `qBittorrent.conf` → a read-only Nix store file on every container start and `nixos-rebuild switch`. Any settings not in `serverConfig` are wiped on restart. Always declare persistent qBittorrent settings (seeding limits, etc.) in `serverConfig`; never rely on in-UI changes surviving a restart.
- Plan mode extension (`modules/programs/pi/extensions/plan-mode/claude-plan-mode.ts`) queues `/plan accept` via `pi.sendUserMessage`, but sendUserMessage bypasses command handling, so the command never runs and `ctx.newSession()` is not triggered. This explains context not clearing after plan acceptance.
- `nix-update --flake` uses `nix-instantiate` + `builtins.getFlake` and fails if `.git` contains `fsmonitor--daemon.ipc` sockets (including in `.git/worktrees`). Remove those sockets before running.
- Zellij defaults to Nushell in this repo; set `GPG_TTY` in Nushell's `env.nu` (use `do -i { ^tty | str trim }`) to keep pinentry on the correct pane TTY.
- `packages/claude-code/default.nix` uses the GCS binary (same source as Homebrew). On Linux: explicit `patchelf --set-interpreter` only, with `dontPatchELF = true` and `dontStrip = true` to protect the Bun standalone payload.
- `~/.config/lazygit/config.yml` is Home Manager managed and symlinked into `/nix/store`; edit `profiles/home-manager/dev.nix` (`lazygitConfig`) instead of editing the live config path.
- On nexus, `dumpd` (rev `7be111f6`) can drive host-wide OOM during uploads: `store_big_blob` can return early on `content_hash` dedupe without draining the request body, while `dumpc upload_dir` sends up to 8 files in parallel. With `container@lc-dump` `MemoryMax=infinity`, memory+swap can be exhausted, leading to `systemd-machined`/`systemd-journald` watchdog failures and a “ping responds but services/SSH dead” freeze until forced reboot.
