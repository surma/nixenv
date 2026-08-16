---
name: hetzner
description: Manage Hetzner Cloud servers via the hcloud CLI. Use when the user asks to list, create, delete, resize, rebuild, or manage servers, enable rescue mode, manage SSH keys, or perform any Hetzner Cloud operation.
compatibility: Requires a Hetzner Cloud API token at /var/lib/credentials/scout/hetzner-cloud-api-token.
---

# Hetzner Cloud Management

Manage Hetzner Cloud servers via the `hcloud` CLI.

## Setup

The API token is stored at `/var/lib/credentials/scout/hetzner-cloud-api-token`. Export it before running any `hcloud` command:

```bash
export HCLOUD_TOKEN=$(cat /var/lib/credentials/scout/hetzner-cloud-api-token)
```

The `hcloud` CLI is not installed by default. Run it via Nix:

```bash
nix shell nixpkgs#hcloud -c hcloud <command>
```

Or for multiple commands in one session:

```bash
export HCLOUD_TOKEN=$(cat /var/lib/credentials/scout/hetzner-cloud-api-token)
nix shell nixpkgs#hcloud -c bash -c '<commands>'
```

## Common Operations

### List servers

```bash
hcloud server list
```

### Server details

```bash
hcloud server describe <name-or-id>
```

### Enable rescue mode

Activates rescue for the next boot. You must reset the server afterward.

```bash
hcloud server enable-rescue <name-or-id> --type linux64
```

This prints a root password for the rescue system.

### Reset (reboot) a server

```bash
hcloud server reset <name-or-id>
```

### Disable rescue mode

```bash
hcloud server disable-rescue <name-or-id>
```

### Rebuild a server (reinstall OS)

```bash
hcloud server rebuild <name-or-id> --image ubuntu-24.04
```

### Power off / on

```bash
hcloud server poweroff <name-or-id>
hcloud server poweron <name-or-id>
```

### SSH keys

```bash
hcloud ssh-key list
hcloud ssh-key create --name <name> --public-key-from-file <path>
```

### Create a server

```bash
hcloud server create \
  --name <name> \
  --type cx22 \
  --image ubuntu-24.04 \
  --location hel1 \
  --ssh-key <key-name>
```

### Delete a server

```bash
hcloud server delete <name-or-id>
```

## NixOS Installation via Rescue Mode

To install NixOS on a Hetzner Cloud server:

1. Enable rescue mode and reset:
   ```bash
   hcloud server enable-rescue <name> --type linux64
   hcloud server reset <name>
   ```

2. Wait for the server to boot into rescue (~30s), then use `nixos-anywhere`:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#<config-name> \
     root@<server-ip>
   ```

3. After install completes, the server reboots into NixOS.

## Important Notes

- Rescue mode is valid for one boot only.
- The rescue root password is shown only once when enabling rescue.
- Always confirm destructive operations (delete, rebuild) with the user first.
- Server names and IPs can change — always verify with `hcloud server list` first.
