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
    inputs.home-manager.nixosModules.home-manager
    ../nixos/base.nix

    ../secrets
  ];

  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "generic-nixos";
  networking.networkmanager.enable = true;

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmbook
  ];

  environment.systemPackages = with pkgs; [
    helix
    zeiilj
  ];

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../home-manager/base.nix
        ../home-manager/dev.nix
        ../home-manager/nixdev.nix
        ../home-manager/linux.nix
        ../home-manager/workstation.nix

        ../home-manager/unfree-apps.nix
      ];

      config = {
        allowedUnfreeApps = [
          "claude-code"
        ];

        home.packages = (
          with pkgs;
          [
          ]
        );

        home.stateVersion = "25.05";

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#generic-nixos";
      };
    };

  system.stateVersion = "25.05";
}
