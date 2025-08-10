{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../home-manager/unfree-apps.nix
    ./surmedge-hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../nixos/base.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "surmedge";
  networking.networkmanager.enable = true;

  programs.zsh.enable = true;

  home-manager.users.surma =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../home-manager/claude-code

        ../home-manager/base.nix
        ../home-manager/dev.nix
        ../home-manager/nixdev.nix
        ../home-manager/linux.nix
        ../home-manager/workstation.nix
        ../home-manager/cloud.nix

        ../home-manager/unfree-apps.nix
      ];

      config = {
        allowedUnfreeApps = [
          "claude-code"
        ];

        home.packages = (
          with pkgs;
          [
            nftables
          ]
        );

        home.stateVersion = "25.05";

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmedge";

        programs.claude-code.enable = true;
        defaultConfigs.claude-code.enable = true;
      };
    };

  networking.firewall.enable = false;
  networking.nftables.enable = true;
  networking.nftables.ruleset = ''
    table inet filter {
      chain output {
        type filter hook output priority 0;
        policy accept;
      }
      chain input {
        type filter hook input priority 0;
        policy drop;
        iif "lo" accept
        tcp dport {80, 22, 8080} accept
        ct state established,related accept
      }
    }
    table ip nat {
      chain prerouting {
        type nat hook prerouting priority 0;
        tcp dport 80 dnat to :8080
      }
    }
  '';
  services.openssh.enable = true;

  system.stateVersion = "25.05";
}
