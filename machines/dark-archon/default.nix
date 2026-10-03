{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  ips = import ../../ips.nix;
in
{
  imports = [
    # NOTE(surma): dark-archon has different hardware than archon. Re-add the
    # matching `inputs.nixos-hardware.nixosModules.<model>` import once the
    # model is known.
    inputs.home-manager.nixosModules.home-manager

    ./hardware.nix

    ../../profiles/nixos/base.nix
    ../../profiles/nixos/nexus-cache.nix
    ../../profiles/nixos/gui/desktop.nix
    ../../profiles/nixos/gui/wayland.nix
    ../../profiles/nixos/gui/sunshine.nix
    ../../profiles/nixos/platform/laptop.nix
    ../../profiles/nixos/home-printer.nix
  ];

  # intel_cvs (Intel Vision Sensing Controller) claims the wake GPIO that all
  # four CS35L57 speaker amps need for their spk-id-gpios, so the amps fail to
  # probe. The upstream fix is not in 7.2.y yet, so blacklist the module; the
  # cost is losing human-presence detection.
  boot.blacklistedKernelModules = [ "intel_cvs" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  # Dell ships PD, Thunderbolt and BIOS firmware through LVFS. Plugging in
  # external monitors hard-powers this machine off, and the kernel blames the
  # firmware outright:
  #   ucsi_acpi USBC000:00: con1: Firmware bug: duplicate partner altmode
  #   SVID 0xff01 ... please contact the BIOS vendor to fix this issue
  # followed by GET_CONNECTOR_STATUS timing out and the power going. BIOS was
  # 1.8.2 (2026-05-22) when that happened.
  services.fwupd.enable = true;

  # TODO: Skip hibernation until we have fixed the touchpad problem.
  services.logind.lidSwitch = "suspend";

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", TAG+="uaccess"
  '';

  # rkvm receives the keyboard and mouse of archon. The server side and the
  # switch keys are in machines/archon/default.nix.
  services.rkvm.client = {
    enable = true;
    settings = {
      server = "${ips.hosts.archon.ip}:5258";
      certificate = ../archon/rkvm-certificate.pem;
      # rkvm reads the password only from its config file. The placeholder
      # keeps the real value out of the Nix store. ExecStartPre below
      # replaces it.
      password = "@RKVM_PASSWORD@";
    };
  };

  secrets.items.rkvm-password = {
    target = "/etc/rkvm/password";
    mode = "0600";
  };

  systemd.services.rkvm-client = {
    requires = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig = {
      RuntimeDirectory = "rkvm";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = pkgs.writeShellScript "rkvm-client-config" ''
        ${pkgs.coreutils}/bin/install -m 0600 ${
          (pkgs.formats.toml { }).generate "rkvm-client.toml" config.services.rkvm.client.settings
        } /run/rkvm/client.toml
        ${pkgs.replace-secret}/bin/replace-secret @RKVM_PASSWORD@ /etc/rkvm/password /run/rkvm/client.toml
      '';
      # rkvm-client exits when it cannot reach the server, and a switch to a
      # new configuration then reports the unit as failed. This happens when
      # archon is down or this laptop is away from home. So wait until the
      # server port answers. Other rkvm errors still make the unit fail.
      ExecStart = lib.mkForce (
        pkgs.writeShellScript "rkvm-client-start" ''
          until ${pkgs.coreutils}/bin/timeout 3 ${pkgs.runtimeShell} -c \
            '</dev/tcp/${
              lib.replaceStrings [ ":" ] [ "/" ] config.services.rkvm.client.settings.server
            }' 2>/dev/null; do
            ${pkgs.coreutils}/bin/sleep 5
          done
          exec ${config.services.rkvm.package}/bin/rkvm-client /run/rkvm/client.toml
        ''
      );
    };
  };

  networking.hostName = "dark-archon"; # Define your hostname.

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
  ];

  programs.obs-studio.enable = true;

  # Firefox picks the first capture-capable V4L2 device. Reserve video0 for
  # OBS Cam: it is hidden while inactive (exclusive_caps) and becomes the
  # default camera while OBS is streaming to it.
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=0 card_label="OBS Cam" exclusive_caps=1
  '';

  programs.signal.enable = true;

  users.users.surma = {
    description = "Surma";

    # For flashing ESP32 boards over USB serial (e.g. the XIAO C6).
    extraGroups = [ "dialout" ];

    # nexus runs services.key-poller and SSHes in as surma to read the
    # Shopify key when shopisurm and archon are unreachable. Merges with the
    # `surma` key that profiles/nixos/base.nix already installs.
    openssh.authorizedKeys.keys = with config.secrets.keys; [
      nexus
    ];
  };

  home-manager.users.surma = import ./home.nix;

  system.stateVersion = "26.05"; # Did you read the comment?
}
