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
      system-manager,
      nix-system-graphics,
      nixos-hardware,
      home-manager,
      ...
    }:
    let
      loadHomeManager = import ./load-home-manager.nix inputs;
      loadLinux = import ./load-linux.nix inputs;
      loadDarwin = import ./load-darwin.nix inputs;
      loadAndroid = import ./load-android.nix inputs;
      loadNixos = import ./load-nixos.nix inputs;
    in
    {
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
        surmpi = loadLinux {
          system = "aarch64-linux";
          machine = ./machines/surmpi.nix;
        };
      };

      homeConfigurations = {
        surmserver = loadHomeManager {
          system = "aarch64-linux";
          machine = ./machines/surmserver.nix;
        };
        generic-aarch64-linux = loadHomeManager {
          system = "aarch64-linux";
          machine = ./machines/generic-linux.nix;
        };
      };

      nixOnDroidConfigurations = {
        generic-android = loadAndroid {
          system = "aarch64-linux";
          machine = ./machines/generic-android.nix;
        };
        surmpixel = loadAndroid {
          system = "aarch64-linux";
          machine = ./machines/surmpixel.nix;
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
      };
    }
    // (flake-utils.lib.eachDefaultSystem (system: rec {
      packages = {
        jupyterDeno = nixpkgs.legacyPackages.${system}.callPackage ./extra-pkgs/jupyter { };
        opencode = nixpkgs.legacyPackages.${system}.callPackage ./extra-pkgs/opencode { };
        claude = nixpkgs.legacyPackages.${system}.callPackage ./extra-pkgs/claude-code { };
        fetch-mcp = nixpkgs.legacyPackages.${system}.callPackage ./extra-pkgs/fetch-mcp { };
        browser-mcp = nixpkgs.legacyPackages.${system}.callPackage ./extra-pkgs/browser-mcp { };
      };
      apps = {
        jupyterDeno = {
          type = "app";
          program = "${packages.jupyterDeno}/bin/jupyter-start";
        };
      };
    }));
}
