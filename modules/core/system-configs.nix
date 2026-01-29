{ lib, config, inputs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    nixosConfigurations = mkOption {
      type = types.lazyAttrsOf (types.deferredModuleWith {
        staticModules = [ ];
      });
      default = {};
      description = "NixOS system configurations";
    };

    darwinConfigurations = mkOption {
      type = types.lazyAttrsOf (types.deferredModuleWith {
        staticModules = [ ];
      });
      default = {};
      description = "nix-darwin system configurations";
    };

    homeConfigurations = mkOption {
      type = types.lazyAttrsOf (types.deferredModuleWith {
        staticModules = [ ];
      });
      default = {};
      description = "home-manager configurations";
    };

    nixOnDroidConfigurations = mkOption {
      type = types.lazyAttrsOf (types.deferredModuleWith {
        staticModules = [ ];
      });
      default = {};
      description = "nix-on-droid configurations";
    };

    systemConfigurations = mkOption {
      type = types.lazyAttrsOf (types.deferredModuleWith {
        staticModules = [ ];
      });
      default = {};
      description = "system-manager configurations";
    };
  };

  config.flake = {
    nixosConfigurations = lib.mapAttrs (name: cfg:
      inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";  # Default, can be overridden in machine config
        modules = [
          cfg
          inputs.home-manager.nixosModules.home-manager
          ({ config, ... }: {
            nixpkgs.overlays = [
              (import ../../overlays/extra-pkgs { inherit inputs; })
            ];
            home-manager = {
              sharedModules = [{
                nixpkgs.overlays = [
                  (import ../../overlays/extra-pkgs { inherit inputs; })
                ];
              }];
              extraSpecialArgs = {
                inherit inputs;
                systemManager = "home-manager";
              };
            };
          })
        ];
        specialArgs = {
          inherit inputs;
          system = "x86_64-linux";
          systemManager = "nixos";
        };
      }
    ) config.nixosConfigurations;

    darwinConfigurations = lib.mapAttrs (name: cfg:
      inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";  # Default, can be overridden
        modules = [
          cfg
          inputs.home-manager.darwinModules.home-manager
          ({ config, ... }: {
            nixpkgs.overlays = [
              (import ../../overlays/extra-pkgs { inherit inputs; })
            ];
            users.users.${config.system.primaryUser} = {
              name = config.system.primaryUser;
              home = "/Users/${config.system.primaryUser}";
            };
            home-manager = {
              sharedModules = [{
                nixpkgs.overlays = [
                  (import ../../overlays/extra-pkgs { inherit inputs; })
                ];
              }];
              extraSpecialArgs = {
                inherit inputs;
                systemManager = "home-manager";
              };
            };
          })
        ];
        specialArgs = {
          inherit inputs;
          system = "aarch64-darwin";
          systemManager = "nix-darwin";
        };
      }
    ) config.darwinConfigurations;

    homeConfigurations = lib.mapAttrs (name: cfg:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;  # Default
        modules = [
          cfg
          {
            nixpkgs.overlays = [
              (import ../../overlays/extra-pkgs { inherit inputs; })
            ];
          }
        ];
        extraSpecialArgs = {
          inherit inputs;
          system = "x86_64-linux";
          systemManager = "home-manager";
        };
      }
    ) config.homeConfigurations;

    nixOnDroidConfigurations = lib.mapAttrs (name: cfg:
      inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [ cfg ];
        extraSpecialArgs = {
          inherit inputs;
          systemManager = "nix-on-droid";
        };
      }
    ) config.nixOnDroidConfigurations;

    systemConfigs = lib.mapAttrs (name: cfg:
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
