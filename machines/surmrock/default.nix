{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix


    ../../apps/hate
    # ../../apps/traefik.nix
    # ../../apps/music
    # ../../apps/torrent
    # ../../apps/lidarr
    # ../../apps/prowlarr
    # ../../apps/sonarr
    # ../../apps/radarr
  ];
  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  home-manager.users.surma = import ./home.nix;
}
