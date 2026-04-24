{
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ../../profiles/nixos/base.nix
  ];

  networking.hostName = "citadel";

  nix.settings.require-sigs = false;
  nix.settings.max-jobs = 4;
  nix.settings.cores = 2;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.firewall.enable = false;
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  services.openssh.enable = true;

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
