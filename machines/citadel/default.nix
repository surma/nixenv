{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ../../profiles/nixos/base.nix

    ../../modules/nixos/hyprland
    ../../modules/nixos/1password-wrapper
    ../../modules/services/surmhosting
    ./service-nixos-admin.nix
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

  # Serial debug console on UART2 (40-pin header pins 8/10, GND on pin 6).
  # 1.5 Mbaud matches what the DT's chosen/stdout-path advertises and what
  # BL31/EDK2 use, so we get a continuous output stream from firmware through
  # to userspace with no baud rate switch in the middle.
  # earlycon covers the gap between firmware and full kernel init -- the
  # exact window in which fusb302-test crashes on the MBP charger.
  boot.kernelParams = [
    "earlycon=uart8250,mmio32,0xfeb50000"
    "console=tty1"
    "console=ttyS2,1500000n8"
  ];

  # Serial getty so we can log in over the UART if the network is down.
  systemd.services."serial-getty@ttyS2".enable = true;

  # No big-core OPP cap: verified safe uncapped on the Pi 27 W charger.
  # If switching to the MBP charger or 65 W GaN, re-add a 2016 MHz cap.
  # See Brain: 7awkp1jk Chapter 8.

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
  services.tailscale.enable = true;

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "citadel";
  services.surmhosting.containeruser.uid = config.users.users.surma.uid;
  services.surmhosting.externalInterface = "wlP2p33s0";

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
