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
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
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
        ../../profiles/home-manager/core.nix
        ../../profiles/home-manager/extras.nix
        ../../profiles/home-manager/dev.nix
        ../../profiles/home-manager/nixdev.nix
        ../../profiles/home-manager/linux.nix
        ../../profiles/home-manager/workstation.nix

      ];

      config = {
        home.packages = (
          with pkgs;
          [
          ]
        );

        home.stateVersion = "25.05";
      };
    };

  system.stateVersion = "25.05";
}
