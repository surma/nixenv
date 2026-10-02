{
  lib,
  osConfig,
  pkgs,
  ...
}:
# Hyprland-specific user settings. ./wayland.nix imports this profile.
{
  config = lib.mkIf (osConfig.gui.compositor == "hyprland") {
    wayland.windowManager.hyprland.enable = true;
    defaultConfigs.hyprland.enable = true;
    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      hl.config({
          input = {
              repeat_delay = 225,
              repeat_rate = 25,
          },
      })
    '';

    programs.hyprsunset.enable = true;
    programs.hyprpaper.enable = true;
    defaultConfigs.hyprpaper.enable = true;

    customScripts.toggle-sunset.enable = true;
    customScripts.toggle-sunset.asDesktopItem = true;
    customScripts.wallpaper-shuffle.enable = true;
    customScripts.wallpaper-shuffle.asDesktopItem = true;
  };
}
