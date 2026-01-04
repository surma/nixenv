{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager

    ./hardware.nix

    ../../home-manager/unfree-apps.nix
    ../../nixos/base.nix
    ../../nixos/hyprland.nix

    ../../nixos/_1password-wrapper.nix

    # ../../secrets
  ];

  allowedUnfreeApps = [ "1password" ];
  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  fonts.packages = with pkgs; [ fira-code ];

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;
  networking.hostName = "forge";
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;
  programs.firefox.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    hyprlock
    pavucontrol
    hyprsunset
    pciutils
    usbutils
  ];

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
    ];
    shell = pkgs.zsh;
  };

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../../home-manager/opencode

        ../../home-manager/base.nix
        ../../home-manager/dev.nix
        ../../home-manager/nixdev.nix
        ../../home-manager/linux.nix
        ../../home-manager/workstation.nix
        ../../home-manager/opencode
        ../../home-manager/hyprland
        ../../home-manager/hyprsunset
        ../../home-manager/waybar
        ../../home-manager/hyprpaper
        ../../home-manager/wezterm

        ../../scripts

        ../../home-manager/unfree-apps.nix
      ];

      config = {
        allowedUnfreeApps = [
        ];

        home.packages = (
          with pkgs;
          [
          ]
        );

        home.stateVersion = "25.11";

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#forge";

        programs.opencode.enable = true;
        defaultConfigs.opencode.enable = true;
        customScripts.toggle-sunset.enable = true;
        customScripts.toggle-sunset.asDesktopItem = true;
        customScripts.wallpaper-shuffle.enable = true;
        customScripts.wallpaper-shuffle.asDesktopItem = true;
        gtk = {
          enable = true;
          iconTheme = {
            name = "Papirus-Dark";
            package = pkgs.papirus-icon-theme;
          };
        };
        programs.wezterm.enable = true;
        programs.wezterm.frontend = "OpenGL";
        programs.wezterm.theme = "dark";
        programs.wezterm.fontSize = 10;
        programs.wezterm.window-decorations = null;
        defaultConfigs.wezterm.enable = true;
        wayland.windowManager.hyprland.enable = true;
        defaultConfigs.hyprland.enable = true;
        wayland.windowManager.hyprland.bindings = [
          {
            key = "SHIFT,XF86MonBrightnessUp";
            action.exec = "brightnessctl -d framework_laptop::kbd_backlight set 5%+";
            flags.e = true;
            flags.l = true;
          }
          {
            key = "SHIFT,XF86MonBrightnessDown";
            action.exec = "brightnessctl -d framework_laptop::kbd_backlight set 5%-";
            flags.e = true;
            flags.l = true;
          }
        ];
        programs.waybar.enable = true;
        defaultConfigs.waybar.enable = true;
        programs.hyprsunset.enable = true;
        programs.hyprpaper.enable = true;
        defaultConfigs.hyprpaper.enable = true;

        services.blueman-applet.enable = true;
        services.dunst.enable = true;
      };
    };

  networking.firewall.enable = false;

  services.openssh.enable = true;

  system.stateVersion = "25.11";
}
