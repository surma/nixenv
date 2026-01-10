{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # amber-upstream = {
    #   url = "github:amber-lang/Amber/0.4.0-alpha";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
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
    copyparty = {
      url = "github:9001/copyparty";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    inputs@{
      flake-utils,
      nixpkgs,
      ...
    }:
    let
      overlays = {
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
          overlays = [ overlays.extra-pkgs ];
        };
      in
      rec {
        inherit overlays;
        packages = {
          # Expose custom packages from overlay
          inherit (pkgs) nixenv secrets;
          jupyterDeno = pkgs.jupyter;

          darwinConfigurations = rec {
            generic-darwin = loadDarwin {
              inherit system;
              machine = ./machines/generic-darwin;
            };
            dragoon = loadDarwin {
              inherit system;
              machine = ./machines/dragoon;
            };
            surmbook = dragoon;
            shopisurm = loadDarwin {
              inherit system;
              machine = ./machines/shopisurm;
            };
          };

          systemConfigs = {
            # surmpi = loadLinux {
            #   system = "aarch64-linux";
            #   machine = ./machines/surmpi.nix;
            # };
          };

          homeConfigurations = {
            generic-linux = loadHomeManager {
              inherit system;
              machine = ./machines/generic-linux;
            };
            surmturntable = loadHomeManager {
              inherit system;
              machine = ./machines/surmturntable;
            };
          };

          nixOnDroidConfigurations = {
            generic-android = loadAndroid {
              inherit system;
              machine = ./machines/generic-android;
            };
          };

          nixosConfigurations = rec {
            generic-nixos = loadNixos {
              inherit system;
              machine = ./machines/generic-nixos;
            };
            archon = loadNixos {
              inherit system;
              machine = ./machines/archon;
            };
            surmframework = archon;
            surmrock = loadNixos {
              inherit system;
              machine = ./machines/surmrock;
            };
            nexus = loadNixos {
              inherit system;
              machine = ./machines/nexus;
            };
            pylon = loadNixos {
              inherit system;
              machine = ./machines/pylon;
            };
            surmedge = pylon;
            testcontainer = loadNixos {
              inherit system;
              machine = ./machines/testcontainer;
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
          secrets = {
            type = "app";
            program = "${packages.secrets}/bin/secrets";
          };
        };
      }
    );
}
