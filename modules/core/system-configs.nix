{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;

  programsDir = ../programs;

  programModules =
    builtins.readDir programsDir
    |> lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists (programsDir + "/${name}/default.nix")
    )
    |> lib.attrNames
    |> lib.sort builtins.lessThan
    |> builtins.map (name: programsDir + "/${name}");

  systemProgramModules =
    [
      "obs"
      "signal"
      "telegram"
    ]
    |> builtins.map (name: programsDir + "/${name}");

  # Cross-cutting modules that are not really program modules.
  sharedFeatureModules = [
    ../features/secrets.nix
    ../features/unfree-apps.nix
  ];

  # System-only feature modules.
  systemFeatureModules = [
    ../features/keyd-as-internal.nix
  ];

  # Home-manager-only feature/service modules.
  homeManagerFeatureModules = [
    ../home-manager/agent
    ../features/hyprland.nix
    ../features/screenshot.nix
    ../services/syncthing
  ];

  systemModules = sharedFeatureModules ++ systemFeatureModules ++ systemProgramModules;
  homeManagerModules = sharedFeatureModules ++ homeManagerFeatureModules ++ programModules;
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

    homeConfigurationSystems = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Target system per home-manager configuration (e.g. aarch64-linux).";
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
        ++ systemModules
        ++ [
          (
            { ... }:
            {
              home-manager = {
                sharedModules = homeManagerModules;
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
        ++ systemModules
        ++ [
          (
            { config, ... }:
            {
              users.users.${config.system.primaryUser} = {
                name = config.system.primaryUser;
                home = "/Users/${config.system.primaryUser}";
              };
              home-manager = {
                sharedModules = homeManagerModules;
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
      let
        system =
          config.homeConfigurationSystems.${name}
            or (throw "homeConfigurations.${name}: missing required homeConfigurationSystems.${name}");
      in
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        modules = homeManagerModules ++ [ cfg ];
        extraSpecialArgs = {
          inherit inputs system;
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
