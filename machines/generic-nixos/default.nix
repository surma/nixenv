{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    /etc/nixos/hardware-configuration.nix
    ../../modules/home-manager/unfree-apps
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

  environment.systemPackages = with pkgs; [ ];

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../../profiles/home-manager/base.nix
        ../../profiles/home-manager/dev.nix
        ../../profiles/home-manager/nixdev.nix
        ../../profiles/home-manager/linux.nix
        ../../profiles/home-manager/workstation.nix

        ../../modules/home-manager/unfree-apps
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
