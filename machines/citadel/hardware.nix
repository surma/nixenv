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
  # The SPI flash holds EDK2 UEFI firmware (edk2-rk3588 v1.1) which negotiates
  # USB-PD in the bootloader, giving the board its full power budget before the
  # kernel starts. This is the correct fix; the kernel-side FUSB302 node can
  # stay disabled.
}
