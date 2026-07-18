{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.home-manager.nixosModules.home-manager

    ./hardware.nix

    ../../profiles/nixos/base.nix
    ../../modules/nixos/hyprland

    ../../modules/nixos/framework/suspend-fix.nix
    ../../modules/nixos/framework/wifi-fix.nix

    ../../modules/nixos/shopify-cloudflare-warp
    ../../modules/nixos/1password-wrapper
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.libinput.touchpad.disableWhileTyping = true;

  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.seatd.enable = true;

  services.keyd = {
    enable = true;
    treat-as-internal-keyboard = true;
    keyboards."internal" = {
      ids = [ "0001:0001" ];
      settings = {
        global = {
          overload_tap_timeout = 100;
        };
        main = {
          capslock = "timeout(escape, 100, overload(meh, escape))";
          leftalt = "leftmeta";
          leftmeta = "leftalt";
        };
        "meh:C-A-M" = { };
      };
    };
  };

  networking.hostName = "archon"; # Define your hostname.
  allowedUnfreeApps = [
    "1password"
    "1password-cli"
  ];
  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    keyd
    hyprlock
    tailscale
    pavucontrol
    hyprsunset
    pciutils
    usbutils
  ];

  services.tailscale.enable = true;

  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "surma" ];
  programs.obs-studio.enable = true;

  # Firefox picks the first capture-capable V4L2 device. Reserve video0 for
  # OBS Cam: it is hidden while inactive (exclusive_caps) and becomes the
  # default camera while OBS is streaming to it.
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=0 card_label="OBS Cam" exclusive_caps=1
  '';

  programs.firefox.enable = true;
  programs.signal.enable = true;

  security.polkit.enable = true;
  security.pam.services.hyprlock = { };

  users.users.surma = {
    isNormalUser = true;
    description = "Surma";
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "video"
      "audio"
      "seat"
    ];
    shell = pkgs.zsh;
  };

  home-manager.users.surma = import ./home.nix;

  services.fprintd.enable = true;
  services.udisks2.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?
}
