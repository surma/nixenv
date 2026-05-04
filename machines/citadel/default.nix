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

    ../../modules/services/surmhosting
    ./service-nixos-admin.nix
  ];

  networking.hostName = "citadel";

  nix.settings.require-sigs = false;
  # No nix.settings.max-jobs/cores caps: with mainline U-Boot 2025.10 in SPI
  # negotiating a 100W PD contract, the EDK2-era 15W cap is no longer needed.
  # See Brain: 7awkp1jk (stress test 2026-04-30, 22 stressors, 0 brownouts).
  secrets.identity = "/home/surma/.ssh/id_machine";

  # SPI flash holds mainline U-Boot 2025.10 (flashed 2026-04-30), which boots
  # via extlinux.conf -- not systemd-boot. See Brain: xbkzm7fk, 7awkp1jk.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  hardware.deviceTree.name = "rockchip/rk3588-rock-5b.dtb";

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

  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    (builtins.readFile ../../assets/ssh-keys/id_deploy.pub)
  ];

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
  ];

  users.users.surma.extraGroups = [
    "wheel"
  ];

  services.udisks2.enable = true;
  services.tailscale.enable = true;

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "citadel";
  services.surmhosting.containeruser.uid = config.users.users.surma.uid;
  services.surmhosting.externalInterface = "enP4p65s0";

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
