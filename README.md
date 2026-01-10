# nixenv

My personal Nix configuration for managing multiple systems across Darwin (macOS), NixOS, and Home Manager.

## Quick Start

### Install Nix

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Apply Configuration

```sh
# macOS
nix --extra-experimental-features 'nix-command flakes pipe-operators' \
  run 'github:LnL7/nix-darwin' -- \
  --extra-experimental-features 'nix-command flakes pipe-operators' \
  switch --flake 'github:surma/nixenv#generic-darwin'

# Linux
nix --extra-experimental-features 'nix-command flakes pipe-operators' \
  run 'github:nix-community/home-manager' -- \
  --extra-experimental-features 'nix-command flakes pipe-operators' \
  switch --flake 'github:surma/nixenv#generic-linux'

# NixOS
sudo nixos-rebuild switch \
  --extra-experimental-features 'nix-command flakes pipe-operators' \
  --flake 'github:surma/nixenv#generic-nixos'

# Android (Termux)
nix --extra-experimental-features 'nix-command flakes pipe-operators' \
  run 'github:nix-community/nix-on-droid' -- \
  switch --flake 'github:surma/nixenv#generic-android'
```

## Repository Structure

```
nixenv/
├── machines/           # Machine-specific configurations
│   ├── generic-*/     # Template configurations for fresh installs
│   └── <hostname>/    # Named machine configurations
│
├── modules/           # Reusable Nix modules
│   ├── programs/      # Interactive applications
│   ├── services/      # Background services
│   ├── home-manager/  # Home Manager specific modules
│   ├── nixos/         # NixOS specific modules
│   ├── darwin/        # Darwin specific modules
│   └── defaultConfigs/ # Default configurations (zsh, helix, etc.)
│
├── profiles/          # Configuration bundles
│   ├── home-manager/  # Home Manager profiles
│   ├── darwin/        # Darwin system profiles
│   ├── nixos/         # NixOS system profiles
│   └── nix-on-droid/  # Android/Termux profiles
│
├── overlays/          # Package overlays
│   └── extra-pkgs/    # Custom packages
│
├── apps/              # Custom applications
│   ├── hate/          # Home automation (source fetched via git)
│   ├── writing-prompt/ # Writing prompt app (source fetched via git)
│   └── surmturntable/ # Vinyl forwarding script
│
├── scripts/           # Standalone utility scripts
├── assets/            # Static files (SSH keys, wallpapers, etc.)
├── secrets/           # Encrypted secrets (.age files)
├── lib/               # Library functions
└── flake.nix          # Flake configuration
```

## Secrets Management

This repository uses [age](https://github.com/FiloSottile/age) for encrypting secrets. The secrets management tool is available as a flake app.

### Available Commands

```sh
# Show all available commands
nix run .#secrets

# Re-encrypt all secrets with current public keys
nix run .#secrets -- recrypt

# Re-encrypt specific secrets
nix run .#secrets -- recrypt llm-proxy-secret ssh-keys

# Edit an encrypted file
nix run .#secrets -- edit secrets/llm-proxy-secret.age

# Encrypt a new file
nix run .#secrets -- encrypt myfile.txt

# Encrypt and keep the original
nix run .#secrets -- encrypt --keep-original myfile.txt

# Generate a new machine key
nix run .#secrets -- genkey
```

### Adding a New Machine

1. Generate a key on the new machine:
   ```sh
   nix run .#secrets -- genkey
   ```

2. Add the public key to `secrets/config.nix` in the `keys` section

3. Add the machine to the appropriate secrets in the `secrets` section

4. Re-encrypt the secrets:
   ```sh
   nix run .#secrets -- recrypt
   ```

### Working from a Different Directory

By default, the tool auto-detects the flake root using git. If you need to specify it manually:

```sh
nix run .#secrets -- recrypt --root /path/to/nixenv
```

## Updating Dependencies

### Update all dependencies

```sh
nix flake update
```

### Update specific dependency

```sh
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager
```

## License

Personal configuration - use at your own risk!
