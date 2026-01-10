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
