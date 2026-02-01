{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
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
    dump = {
      url = "git+ssh://git@github.com/surma/dump?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    voice-memos = {
      url = "git+ssh://git@github.com/surma/voice-memos?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    opencode = {
      url = "github:anomalyco/opencode?ref=v1.1.40";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./modules/core
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = { config, system, pkgs, ... }:
        {
          # Apps for commonly used packages
          apps = {
            default = config.apps.nixenv;
            nixenv = {
              type = "app";
              program = "${config.packages.nixenv}/bin/nixenv";
            };
            jupyterDeno = {
              type = "app";
              program = "${config.packages.jupyter}/bin/jupyter-start";
            };
            secrets = {
              type = "app";
              program = "${config.packages.secrets}/bin/secrets";
            };
          };
        };

      # Expose overlays at flake level
      flake.overlays = {
        extra-pkgs = import ./overlays/extra-pkgs { inherit inputs; };
      };
    };
}
