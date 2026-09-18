{
  config,
  pkgs,
  inputs,
  ...
}:
# Template for a new NixOS laptop that I sit at, next to ../generic-nixos for a
# headless or desktop box. To adopt a machine:
#
# 1. Copy this directory to machines/<name> and set networking.hostName.
# 2. Replace /etc/nixos/hardware-configuration.nix with ./hardware.nix.
# 3. Add the nixos-hardware module for the model, and profiles/nixos/platform/framework.nix
#    if it is a Framework.
# 4. Register the machine in modules/core/machines.nix.
# 5. Add the machine key to secrets/config.nix for the items it needs.
#
# This configuration evaluates on any host that has an /etc/nixos
# hardware-configuration.nix, which keeps the template honest.
{
  imports = [
    /etc/nixos/hardware-configuration.nix
    inputs.home-manager.nixosModules.home-manager

    # Framework example:
    # inputs.nixos-hardware.nixosModules.framework-13-7040-amd

    ../../profiles/nixos/base.nix
    ../../profiles/nixos/gui/desktop.nix
    ../../profiles/nixos/gui/hyprland.nix
    ../../profiles/nixos/platform/laptop.nix
    # ../../profiles/nixos/platform/framework.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "generic-nixos-laptop";
  networking.networkmanager.enable = true;

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmbook
  ];

  home-manager.users.surma = {
    imports = [
      ../../profiles/home-manager/core.nix
      ../../profiles/home-manager/extras.nix
      ../../profiles/home-manager/platform/linux.nix
      ../../profiles/home-manager/gui/fonts.nix
      ../../profiles/home-manager/gui/terminal.nix
      ../../profiles/home-manager/gui/gui-apps.nix
      ../../profiles/home-manager/platform/physical.nix
      ../../profiles/home-manager/gui/hyprland.nix
      # ../../profiles/home-manager/platform/framework.nix
      ../../profiles/home-manager/roles/workstation.nix
      ../../profiles/home-manager/roles/dev.nix
      ../../profiles/home-manager/roles/nixdev.nix
    ];

    home.stateVersion = "25.05";
  };

  system.stateVersion = "25.05";
}
