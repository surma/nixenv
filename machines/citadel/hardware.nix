{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/9f755597-9e98-44bc-afda-2a083e87ab80";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2D27-0699";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # USB-PD / power note:
  # The FUSB302 PD chip (i2c4 / 0xfeac0000, addr 0x22) is intentionally left
  # as status="fail" in the upstream kernel DTS (rk3588-rock-5b-5bp-5t.dtsi).
  # The reason: USB-PD negotiation must complete within 5 s of connection, but
  # the board takes longer than that to boot into the kernel driver. The PSU
  # responds with a hard-reset of VBUS, which power-cycles the whole board.
  # Enabling it in a DT overlay reproduces this exactly — do not do this.
  #
  # The SPI flash holds mainline U-Boot 2025.10 (flashed 2026-04-30) which has
  # full FUSB302/TCPM support and negotiates a 20V/5A/100W PD_PPS contract in
  # the bootloader, well before the kernel starts. The board boots via
  # extlinux.conf written by boot.loader.generic-extlinux-compatible. The
  # kernel-side FUSB302 node stays disabled. See Brain: xbkzm7fk, 7awkp1jk.
  #
  # Cold-boot caveat: the kernel TCPM driver hits an RX-FIFO race on first
  # bind, issues a USB-PD Hard Reset, and the board reboots once (~10 s).
  # Subsequent boots and warm reboots are clean. Reichel's v6.17 cache-PD-RX
  # patch is present but addresses a different race; the U-Boot→kernel handoff
  # gap is on his "future work" list.
}
