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

      loadHomeManager = import ./load-home-manager.nix { inherit inputs; };
      loadLinux = import ./load-linux.nix { inherit inputs; };
      loadDarwin = import ./load-darwin.nix { inherit inputs overlays; };
      loadAndroid = import ./load-android.nix { inherit inputs; };
      loadNixos = import ./load-nixos.nix { inherit inputs overlays; };
    in
    {
      inherit overlays;
      darwinConfigurations = {
        surmbook = loadDarwin {
          system = "aarch64-darwin";
          machine = ./machines/surmbook.nix;
        };
        shopisurm = loadDarwin {
          system = "aarch64-darwin";
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
          system = "aarch64-linux";
          machine = ./machines/generic-linux.nix;
        };
        surmturntable = loadHomeManager {
          system = "aarch64-linux";
          machine = ./machines/surmturntable.nix;
        };
      };

      nixOnDroidConfigurations = {
        generic-android = loadAndroid {
          system = "aarch64-linux";
          machine = ./machines/generic-android.nix;
        };
      };

      nixosConfigurations = {
        surmframework = loadNixos {
          system = "x86_64-linux";
          machine = ./machines/surmframework.nix;
        };
        surmrock = loadNixos {
          system = "aarch64-linux";
          machine = ./machines/surmrock.nix;
        };
        surmedge = loadNixos {
          system = "aarch64-linux";
          machine = ./machines/surmedge.nix;
        };
      };

    }
    // (flake-utils.lib.eachDefaultSystem (system: rec {
      packages =
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              overlays.unstable
              overlays.extra-pkgs
            ];
          };
          inherit (pkgs) callPackage;
        in
        {
          jupyterDeno = callPackage ./overlays/extra-pkgs/jupyter { };
          opencode = callPackage ./overlays/extra-pkgs/opencode { };
          claude = callPackage ./overlays/extra-pkgs/claude-code { };
          fetch-mcp = callPackage ./overlays/extra-pkgs/fetch-mcp { };
          browser-mcp = callPackage ./overlays/extra-pkgs/browser-mcp { };
          nixenv = callPackage ./overlays/extra-pkgs/nixenv { };
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
    }));
}
