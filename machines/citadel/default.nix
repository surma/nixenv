{
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ../../profiles/nixos/base.nix

    ../../modules/nixos/hyprland
    ../../modules/nixos/1password-wrapper
  ];

  allowedUnfreeApps = [
    "1password"
    "1password-cli"
  ];

  networking.hostName = "citadel";

  nix.settings.require-sigs = false;
  nix.settings.max-jobs = 4;
  nix.settings.cores = 2;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  networking.firewall.enable = false;
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    hyprlock
    pavucontrol
    hyprsunset
    pciutils
    usbutils
  ];

  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "surma" ];

  programs.obs.enable = true;
  programs.firefox.enable = true;
  programs.signal.enable = true;

  security.polkit.enable = true;
  security.pam.services.hyprlock = { };

  users.users.surma.extraGroups = [
    "networkmanager"
    "wheel"
    "input"
    "video"
    "audio"
  ];

  services.udisks2.enable = true;

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
