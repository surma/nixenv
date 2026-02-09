{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/gamedev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/experiments.nix

    ../../profiles/home-manager/webapps.nix
  ];

  config = {
    allowedUnfreeApps = [
      "spotify"
      "slack"
      "discord"
      "claude-code"
      "obsidian"
    ];

    customScripts.toggle-sunset.enable = true;
    customScripts.toggle-sunset.asDesktopItem = true;
    customScripts.bluetooth-fix.enable = true;
    customScripts.bluetooth-fix.asDesktopItem = true;
    customScripts.wallpaper-shuffle.enable = true;
    customScripts.wallpaper-shuffle.asDesktopItem = true;

    home.packages = (
      with pkgs;
      [
        slack
        nodejs_24
        chromium
        kdePackages.dolphin
        vlc
        qview
      ]
    );

    gtk = {
      enable = true;
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

    home.stateVersion = "24.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmframework";

    programs.spotify.enable = true;
    # programs.spotify.platform = "wayland";
    programs.discord.enable = true;
    # programs.discord.platform = "wayland";
    programs.telegram.enable = true;
    programs.whatsapp.enable = true;
    programs.squoosh.enable = true;
    programs.geforce-now.enable = true;
    programs.xbox-remote-play.enable = true;
    programs.obsidian.enable = false;

    programs.wezterm.enable = true;
    programs.wezterm.frontend = "OpenGL";
    programs.wezterm.theme = "dark";
    programs.wezterm.fontSize = 10;
    programs.wezterm.window-decorations = null;
    defaultConfigs.wezterm.enable = true;

    programs.zellij.wl-clipboard.enable = true;

    services.syncthing.enable = true;
    defaultConfigs.syncthing.enable = true;
    services.syncthing.tray.enable = true;

    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    programs.claude-code.enable = true;
    defaultConfigs.claude-code.enable = true;

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
}
