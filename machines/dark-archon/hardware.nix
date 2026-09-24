{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

# PLACEHOLDER — replace this file with the real hardware-configuration.nix
# generated on the machine (`nixos-generate-config`), then delete this
# comment and the `warnings` entry below.
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  warnings = [
    "machines/dark-archon/hardware.nix is a placeholder. Replace it with the real hardware configuration before deploying."
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "uas"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/mapper/luks-00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."luks-00000000-0000-0000-0000-000000000000".device =
    "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0000";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  boot.initrd.luks.devices."luks-11111111-1111-1111-1111-111111111111".device =
    "/dev/disk/by-uuid/11111111-1111-1111-1111-111111111111";

  swapDevices = [ { device = "/dev/mapper/luks-11111111-1111-1111-1111-111111111111"; } ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
