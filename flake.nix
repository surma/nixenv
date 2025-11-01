{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    amber-upstream = {
      url = "github:amber-lang/Amber";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/hyprland/v0.49.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/98236410ea0fe204d0447149537a924fb71a6d4f";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs@{
      flake-utils,
      nixpkgs,
      ...
    }:
    let
      overlays = {
        unstable = import ./overlays/unstable { inherit inputs; };
        extra-pkgs = import ./overlays/extra-pkgs { inherit inputs; };
      };

      loadHomeManager = import ./load-home-manager.nix { inherit inputs overlays; };
      loadLinux = import ./load-linux.nix { inherit inputs overlays; };
      loadDarwin = import ./load-darwin.nix { inherit inputs overlays; };
      loadAndroid = import ./load-android.nix { inherit inputs overlays; };
      loadNixos = import ./load-nixos.nix { inherit inputs overlays; };
    in
    flake-utils.lib.eachSystem flake-utils.lib.defaultSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            overlays.unstable
            overlays.extra-pkgs
          ];
        };
      in
      rec {
        inherit overlays;
        packages = {
          darwinConfigurations = {
            surmbook = loadDarwin {
              inherit system;
              machine = ./machines/surmbook.nix;
            };
            shopisurm = loadDarwin {
              inherit system;
              machine = ./machines/shopisurm.nix;
            };
          };

          systemConfigs = {
            # surmpi = loadLinux {
            #   system = "aarch64-linux";
            #   machine = ./machines/surmpi.nix;
            # };
          };

          homeConfigurations = {
            generic-aarch64-linux = loadHomeManager {
              inherit system;
              machine = ./machines/generic-linux.nix;
            };
            surmturntable = loadHomeManager {
              inherit system;
              machine = ./machines/surmturntable.nix;
            };
          };

          nixOnDroidConfigurations = {
            generic-android = loadAndroid {
              inherit system;
              machine = ./machines/generic-android.nix;
            };
          };

          nixosConfigurations = {
            generic-nixos = loadNixos {
              inherit system;
              machine = ./machines/generic-nixos.nix;
            };
            surmframework = loadNixos {
              inherit system;
              machine = ./machines/surmframework.nix;
            };
            surmrock = loadNixos {
              inherit system;
              machine = ./machines/surmrock.nix;
            };
            surmedge = loadNixos {
              inherit system;
              machine = ./machines/surmedge.nix;
            };
            testcontainer = loadNixos {
              inherit system;
              machine = ./machines/testcontainer.nix;
            };
          };
        };

        apps = {
          default = apps.nixenv;
          nixenv = {
            type = "app";
            program = "${packages.nixenv}/bin/nixenv";
          };
          jupyterDeno = {
            type = "app";
            program = "${packages.jupyterDeno}/bin/jupyter-start";
          };
        };
      }
    );
}
