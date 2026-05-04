---
name: nexus-admin
description: Deploy NixOS configuration to Nexus or Citadel, inspect deploy history and logs, list containers and systemd units, manage systemd timers, and fetch journal logs — all via the NixOS Admin HTTP API. Use when the user asks to deploy, check deploy status, view service logs, inspect containers, list or trigger timers, or troubleshoot Nexus or Citadel.
compatibility: Requires network access to the NixOS Admin service on the target host.
---

# NixOS Admin

NixOS Admin is an HTTP service that manages NixOS deployments and provides access to systemd journal logs, units, and timers — both on the host and inside systemd-nspawn containers. It runs on both Nexus and Citadel.

**Base URLs:**
- **Nexus:** `http://admin.nexus.hosts.10.0.0.2.nip.io`
- **Citadel:** `http://admin.citadel.hosts.10.0.0.32.nip.io`

All examples below use the Nexus URL. Replace the base URL with the Citadel one when targeting Citadel.

## CRITICAL: deploys require explicit user confirmation

Deploying is a **high-impact, potentially destructive** operation.

1. **Always ask the user for explicit confirmation.** State which host and flake URL will be deployed.
2. **Wait for a clear "yes"** before calling the deploy API.
3. Do not infer approval from the user asking you to make code changes — code changes and deployment are separate steps.
4. If the deploy fails, report the full status and logs to the user. Do not automatically retry or attempt rollback without asking.

## CRITICAL: local vs remote deploys — read this before ANY deploy

The deploy API runs `nixos-rebuild switch` **on the machine where the admin service is running** by default. To deploy to a DIFFERENT machine, you **MUST** pass `target_host` in the request body. Without it, the config will be applied to the machine running the admin API — which **WILL BRICK THE MACHINE** if it's the wrong config (wrong hostname, wrong network config, wrong services).

**Deploy request fields:**
- `flake_url` (string): The NixOS flake to deploy (e.g., `github:surma/nixenv#nexus`)
- `target_host` (string, optional): SSH host to deploy to remotely. If omitted, deploys LOCALLY.
- `use_remote_sudo` (boolean, optional): Use sudo on the remote host.

**Machine topology and correct deploy commands:**

| Target | Admin API | flake_url | target_host | use_remote_sudo |
|--------|-----------|-----------|-------------|-----------------|
| Nexus  | Nexus     | `#nexus`  | *(omit)*    | *(omit)*        |
| Citadel | Citadel  | `#citadel` | *(omit)*   | *(omit)*        |
| Pylon  | Citadel   | `#pylon`  | `"pylon"`   | `false`         |

**Deploying Pylon (via Citadel):**
```bash
curl -X POST http://admin.citadel.hosts.10.0.0.32.nip.io/api/deploy \
  -H 'Content-Type: application/json' \
  -d '{"flake_url":"github:surma/nixenv#pylon","target_host":"pylon"}'
```

The SSH config on Citadel maps `pylon` to `root@surmedge.hosts.surma.link` with the deploy key.

**NEVER send a flake URL with a hostname fragment (e.g. `#pylon`, `#nexus`) to an admin API on a different machine without `target_host`. This applies the wrong NixOS config locally and will make the machine unresponsive.**

## API reference

All endpoints are relative to the base URL above. Use `curl` (via `nix run nixpkgs#curl`) since it may not be on PATH.

### Deploy

#### Start a deploy

```bash
# Deploy from the default flake (github:surma/nixenv#nexus):
curl -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy

# Deploy from a specific branch:
curl -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy \
  -H 'Content-Type: application/json' \
  -d '{"flake_url":"github:surma/nixenv/my-branch#nexus"}'
```

Returns `202 Accepted` with the deploy metadata:

```json
{
  "id": "01JSFQ...",
  "flake_url": "github:surma/nixenv#nexus",
  "status": "running",
  "started_at": "2026-04-22T12:00:00Z",
  "pre_generation": 42
}
```

Returns `409 Conflict` if a deploy is already running.

#### Cancel a running deploy

```bash
curl -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy/<id>/cancel
```

#### List all deploys

```bash
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploys
```

Returns:

```json
{
  "active_id": "01JSFQ...",
  "deploys": [
    {
      "id": "01JSFQ...",
      "flake_url": "github:surma/nixenv#nexus",
      "status": "success",
      "started_at": "2026-04-22T12:00:00Z",
      "finished_at": "2026-04-22T12:05:00Z",
      "pre_generation": 42
    }
  ]
}
```

`active_id` is set when a deploy is currently in progress.

#### Read deploy logs (plain text)

```bash
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploys/<id>/log
```

Returns the full deploy log as plain text.

#### Stream deploy logs (SSE)

```bash
curl -sN http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy/<id>/stream
```

Returns a Server-Sent Events stream. Each `data:` line is a log line. For active deploys, existing lines are replayed first, then new lines stream live.

The stream ends with a line matching `[deploy] DONE:<status>` where status is one of:
- `success` — deploy completed successfully
- `build-failed` — `nixos-rebuild build` failed
- `switch-failed` — `nixos-rebuild switch` failed (automatic rollback is attempted)
- `rollback-failed` — rollback after switch failure also failed (system may be inconsistent)
- `cancelled` — deploy was cancelled

### Deploy statuses

| Status | Meaning |
|---|---|
| `running` | Deploy is in progress |
| `success` | Build and switch both succeeded |
| `build-failed` | `nixos-rebuild build` failed; no changes were applied |
| `switch-failed` | `nixos-rebuild switch` failed; rollback was attempted |
| `rollback-failed` | Both switch and rollback failed; system may be inconsistent |
| `cancelled` | Deploy was stopped before completion |

### Containers

#### List containers

```bash
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/containers
```

Returns:

```json
{
  "containers": ["scout", "other-container"]
}
```

These are systemd-nspawn machines visible via `machinectl list`.

### Systemd units

#### List service units

```bash
# Host units:
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/units

# Units inside a container:
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/units?container=scout'
```

Returns:

```json
{
  "units": [
    {
      "unit": "sshd.service",
      "load": "loaded",
      "active": "active",
      "sub": "running",
      "description": "OpenSSH Daemon"
    }
  ]
}
```

### Systemd timers

#### List timers

```bash
# Host timers:
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers

# Timers inside a container:
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers?container=scout'
```

Returns:

```json
{
  "timers": [
    {
      "unit": "logrotate.timer",
      "activates": "logrotate.service",
      "next": "Sun 2026-05-04 00:00:00 BST",
      "left": "in 12h 30min",
      "last": "Sat 2026-05-03 00:00:00 BST",
      "passed": "11h 30min ago"
    }
  ]
}
```

Fields `next`, `left`, `last`, and `passed` may be `null` if the timer has never run or has no scheduled next run.

If the container is unreachable, returns an empty list rather than an error.

#### Trigger a timer (run now)

```bash
# Trigger a timer's associated service on the host:
curl -s -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers/logrotate.service/trigger

# Trigger inside a container:
curl -s -X POST 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers/logrotate.service/trigger?container=scout'
```

The `{unit}` in the URL is the **activates** service name (not the timer unit).

Returns on success:

```json
{
  "status": "started",
  "unit": "logrotate.service"
}
```

Returns `502` if the container is unreachable, `500` for other failures.

### Journal logs

#### Fetch logs for a unit

```bash
# Basic usage (last 100 lines):
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/logs?unit=sshd.service'

# Inside a container:
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/logs?unit=opencode.service&container=scout'

# With options:
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/logs?unit=sshd.service&lines=200&boot=true&since=-1h'
```

Returns plain text (journalctl output in `short-iso` format).

**Query parameters:**

| Parameter | Required | Description |
|---|---|---|
| `unit` | yes | Systemd unit name (e.g. `sshd.service`) |
| `container` | no | Container name to query (omit for host) |
| `lines` | no | Number of lines to return (default: 100, max: 10000) |
| `boot` | no | `true` to limit to current boot |
| `since` | no | Show entries since this time (e.g. `-1h`, `2026-01-01`) |
| `until` | no | Show entries until this time |

### Health check

```bash
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/health
```

Returns `200 OK` with `{"status":"ok"}`. Useful for verifying the service is up.

## Recommended workflows

### Deploy from main

```bash
# 1. Start the deploy (uses default flake: github:surma/nixenv#nexus)
DEPLOY=$(curl -s -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy)
ID=$(echo "$DEPLOY" | jq -r '.id')

# 2. Stream logs until done
curl -sN "http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy/$ID/stream"
```

### Deploy from a branch

```bash
curl -s -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploy \
  -H 'Content-Type: application/json' \
  -d '{"flake_url":"github:surma/nixenv/my-feature-branch#nexus"}'
```

### Check what's running in a container

```bash
# List all service units in the scout container
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/units?container=scout' | jq '.units[] | select(.sub != "dead")'
```

### Troubleshoot a service

```bash
# 1. Check the unit status
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/units?container=scout' | jq '.units[] | select(.unit == "opencode.service")'

# 2. Fetch recent logs
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/logs?unit=opencode.service&container=scout&lines=200'

# 3. Fetch logs from the last hour only
curl -s 'http://admin.nexus.hosts.10.0.0.2.nip.io/api/logs?unit=opencode.service&container=scout&since=-1h'
```

### List and trigger timers

```bash
# List all timers on the host
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers | jq '.timers[] | {unit, activates, next, last}'

# Manually trigger a backup (runs the associated service immediately)
curl -s -X POST http://admin.nexus.hosts.10.0.0.2.nip.io/api/timers/restic-backups-nexus-local.service/trigger
```

### Check deploy history

```bash
# List recent deploys
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploys | jq '.deploys[:5]'

# Read logs for a specific past deploy
curl -s http://admin.nexus.hosts.10.0.0.2.nip.io/api/deploys/<id>/log
```

## Tips

- The default flake URL depends on the host: `github:surma/nixenv#nexus` for Nexus, `github:surma/nixenv#citadel` for Citadel. You only need to specify `flake_url` when deploying from a branch or a different flake.
- Only one deploy can run at a time per host. Check `active_id` in the list response to see if one is in progress.
- Deploy phases: the service runs `nixos-rebuild build` first, then `nixos-rebuild switch`. If switch fails, it automatically attempts rollback to the pre-deploy generation.
- The web UI is available at the base URL in a browser for manual use.
- `curl` may not be on PATH in Scout's container — use `nix run nixpkgs#curl -- <args>` as a workaround.
