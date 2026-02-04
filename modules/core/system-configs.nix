{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;

  # Feature modules that work at system level (nixos/darwin)
  # These handle both system-level AND nested home-manager configs
  systemFeatures = [
    ../features/secrets.nix
    ../features/unfree-apps.nix
    ../features/signal.nix
    ../features/telegram.nix
    ../features/obs.nix
    ../features/keyd-as-internal.nix
    # hyprland is Linux-only, loaded via nestedHomeManagerFeatures only
    # obsidian is provided by home-manager built-in
  ];

  # Feature modules for nested home-manager (within nixos/darwin)
  # Includes cross-platform features that support home-manager context
  nestedHomeManagerFeatures = [
    ../features/unfree-apps.nix
    ../features/secrets.nix
    ../features/signal.nix
    ../features/telegram.nix
    ../features/obs.nix
    # obsidian is provided by home-manager built-in
    ../features/hyprland.nix
    ../features/zellij.nix
    ../features/nushell.nix
    ../features/browser-mcp.nix
    ../features/mcp-nixos.nix
    ../features/fetch-mcp.nix
    ../features/mcp-playwright.nix
    ../features/handy.nix
    ../features/ghostty.nix
    ../features/wezterm.nix
    ../features/waybar.nix
    ../features/screenshot.nix
    ../features/hyprsunset.nix
    ../features/hyprpaper.nix
    ../features/pi-coding-agent.nix
    ../features/claude-code.nix
    ../features/opencode.nix
    ../features/syncthing.nix
    ../features/spotify.nix
    # discord and obsidian are provided by home-manager built-in
  ];

  # Feature modules for standalone home-manager configs
  # Only include home-manager compatible features
  standaloneHomeManagerFeatures = nestedHomeManagerFeatures;
in
{
  options = {
    nixosConfigurations = mkOption {
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [ ];
        }
      );
      default = { };
      description = "NixOS system configurations";
    };

    darwinConfigurations = mkOption {
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [ ];
        }
      );
      default = { };
      description = "nix-darwin system configurations";
    };

    homeConfigurations = mkOption {
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [ ];
        }
      );
      default = { };
      description = "home-manager configurations";
    };

    nixOnDroidConfigurations = mkOption {
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [ ];
        }
      );
      default = { };
      description = "nix-on-droid configurations";
    };

    systemConfigurations = mkOption {
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [ ];
        }
      );
      default = { };
      description = "system-manager configurations";
    };
  };

  config.flake = {
    nixosConfigurations = lib.mapAttrs (
      name: cfg:
      inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # Default, can be overridden in machine config
        modules = [
          cfg
          inputs.home-manager.nixosModules.home-manager
        ]
        ++ systemFeatures
        ++ [
          (
            { config, ... }:
            {
              home-manager = {
                sharedModules = nestedHomeManagerFeatures;
                extraSpecialArgs = {
                  inherit inputs;
                  systemManager = "home-manager";
                };
              };
            }
          )
        ];
        specialArgs = {
          inherit inputs;
          system = "x86_64-linux";
          systemManager = "nixos";
        };
      }
    ) config.nixosConfigurations;

    darwinConfigurations = lib.mapAttrs (
      name: cfg:
      inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin"; # Default, can be overridden
        modules = [
          cfg
          inputs.home-manager.darwinModules.home-manager
        ]
        ++ systemFeatures
        ++ [
          (
            { config, ... }:
            {
              users.users.${config.system.primaryUser} = {
                name = config.system.primaryUser;
                home = "/Users/${config.system.primaryUser}";
              };
              home-manager = {
                sharedModules = nestedHomeManagerFeatures;
                extraSpecialArgs = {
                  inherit inputs;
                  systemManager = "home-manager";
                };
              };
            }
          )
        ];
        specialArgs = {
          inherit inputs;
          system = "aarch64-darwin";
          systemManager = "nix-darwin";
        };
      }
    ) config.darwinConfigurations;

    homeConfigurations = lib.mapAttrs (
      name: cfg:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; # Default
        modules = standaloneHomeManagerFeatures ++ [
          cfg
        ];
        extraSpecialArgs = {
          inherit inputs;
          system = "x86_64-linux";
          systemManager = "home-manager";
        };
      }
    ) config.homeConfigurations;

    nixOnDroidConfigurations = lib.mapAttrs (
      name: cfg:
      inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [ cfg ];
        extraSpecialArgs = {
          inherit inputs;
          systemManager = "nix-on-droid";
        };
      }
    ) config.nixOnDroidConfigurations;

    systemConfigs = lib.mapAttrs (
      name: cfg:
      inputs.system-manager.lib.makeSystemConfig {
        modules = [ cfg ];
        extraSpecialArgs = {
          inherit inputs;
          systemManager = "system-manager";
        };
      }
    ) config.systemConfigurations;
  };
}
