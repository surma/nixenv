{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/ai.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/experiments.nix

    ../../profiles/home-manager/webapps.nix
  ];

  config = {
    allowedUnfreeApps = [
      "obsidian"
    ];

    customScripts.toggle-sunset.enable = true;
    customScripts.toggle-sunset.asDesktopItem = true;
    customScripts.wallpaper-shuffle.enable = true;
    customScripts.wallpaper-shuffle.asDesktopItem = true;

    home.packages = (
      with pkgs;
      [
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

    home.stateVersion = "25.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#citadel";

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

    secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    wayland.windowManager.hyprland.enable = true;
    defaultConfigs.hyprland.enable = true;
    programs.waybar.enable = true;
    defaultConfigs.waybar.enable = true;
    programs.hyprsunset.enable = true;
    programs.hyprpaper.enable = true;
    defaultConfigs.hyprpaper.enable = true;

    services.blueman-applet.enable = true;
    services.dunst.enable = true;
  };
}
