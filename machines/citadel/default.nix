{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ../../profiles/nixos/base.nix
  ];

  networking.hostName = "citadel";

  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.firewall.enable = false;

  services.openssh.enable = true;

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
