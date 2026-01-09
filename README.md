# nixenv

My personal Nix configuration for managing multiple systems across Darwin (macOS), NixOS, and Home Manager.

## Repository Structure

```
nixenv/
├── machines/           # Machine-specific configurations
│   ├── archon/        # NixOS workstation (Framework laptop)
│   ├── dragoon/       # Darwin workstation (macOS)
│   ├── nexus/         # NixOS home server
│   ├── pylon/         # NixOS edge server
│   ├── shopisurm/     # Darwin work machine
│   ├── surmrock/      # NixOS home server
│   ├── surmturntable/ # Home Manager standalone
│   └── generic-*/     # Template configurations
│
├── modules/           # Reusable Nix modules
│   ├── programs/      # Interactive applications (discord, signal, etc.)
│   ├── services/      # Background services (syncthing, surmhosting, etc.)
│   ├── home-manager/  # Home Manager specific modules
│   ├── nixos/         # NixOS specific modules
│   ├── darwin/        # Darwin specific modules
│   ├── secrets/       # Secrets management module
│   └── defaultConfigs/ # Default configuration modules (zsh, helix, etc.)
│
├── profiles/          # Configuration bundles
│   ├── home-manager/  # Home Manager profiles (base, dev, workstation, etc.)
│   ├── darwin/        # Darwin system profiles
│   ├── nixos/         # NixOS system profiles
│   └── nix-on-droid/  # Android/Termux profiles
│
├── overlays/          # Package overlays
│   └── extra-pkgs/    # Custom packages (claude-code, opencode, MCP servers)
│
├── apps/              # Custom applications with source code
│   ├── hate/          # Home automation app
│   ├── writing-prompt/ # Writing prompt web app
│   └── surmturntable/ # Vinyl forwarding script
│
├── scripts/           # Standalone utility scripts
│   ├── denix/         # Nix development helper
│   ├── ghclone/       # GitHub clone helper
│   └── ...
│
├── assets/            # Static files
│   ├── ssh-keys/      # SSH public keys
│   ├── gpg-keys/      # GPG public keys
│   └── wallpapers/    # Desktop wallpapers
│
├── secrets/           # Encrypted secrets (.age files)
│   ├── config.nix     # Secret definitions and key mappings
│   └── *.age          # Encrypted secret files
│
├── lib/               # Library functions
│   ├── mk-multi-system-module.nix  # Multi-system module builder
│   └── ...
│
└── flake.nix          # Flake configuration
```

## Key Concepts

### Modules vs Profiles

- **Modules** (`modules/`): Reusable components that define options and configuration for specific programs or services. They can be imported and configured independently.
  
- **Profiles** (`profiles/`): Pre-configured bundles that import and enable multiple modules with sensible defaults. Think of them as "meta-configurations" for common use cases.

### Multi-System Modules

Modules in `modules/programs/` and `modules/services/` often use the `mk-multi-system-module` pattern, allowing a single module definition to work across:
- nix-darwin (macOS)
- NixOS
- Home Manager
- system-manager

### Machine Organization

Each machine has its own directory under `machines/` containing:
- `default.nix` - Main machine configuration
- `hardware.nix` - Hardware-specific settings (NixOS only)
- Machine-specific secrets and service configurations (if needed)

## Usage

### Building a Configuration

```bash
# Darwin (macOS)
darwin-rebuild switch --flake .#dragoon

# NixOS
nixos-rebuild switch --flake .#archon

# Home Manager (standalone)
home-manager switch --flake .#surmturntable
```

### Managing Secrets

Secrets are encrypted using age with SSH keys. See `secrets/config.nix` for secret definitions.

```bash
# Encrypt a secret
age -e -i ~/.ssh/id_machine -o secrets/new-secret.age

# Add to secrets/config.nix
```

### Adding a New Module

1. Create module directory: `modules/{programs,services,home-manager,nixos,darwin}/<name>/`
2. Add `default.nix` with module definition
3. Import in machine or profile configuration
4. Enable with `programs.<name>.enable = true` or `services.<name>.enable = true`

### Creating a New Machine

1. Create directory: `machines/<name>/`
2. Add `default.nix` with machine configuration
3. Import appropriate profiles and modules
4. Add to `flake.nix` outputs
5. Build with appropriate rebuild command

## Special Features

### Custom Hosting Service

The `modules/services/surmhosting` module provides a sophisticated hosting infrastructure with:
- Traefik reverse proxy
- NixOS container management
- Automatic TLS with Let's Encrypt
- Docker integration

### Default Configs

The `modules/defaultConfigs/` directory contains opinionated default configurations for common tools that can be easily enabled:
- `defaultConfigs.zsh.enable = true`
- `defaultConfigs.helix.enable = true`
- `defaultConfigs.aerospace.enable = true` (macOS)
- etc.

## License

Personal configuration - use at your own risk!
