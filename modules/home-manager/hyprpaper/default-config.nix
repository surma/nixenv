{
  pkgs,
  config,
  lib,
  ...
}:
let
  wallpaper = config.defaultConfigs.hyprpaper.wallpaper;
in
with lib;
{
  options = {
    defaultConfigs.hyprpaper = {
      enable = mkEnableOption "";
      wallpaper = mkOption {
        type = types.path;
        description = "The wallpaper that hyprpaper shows at start.";
      };
    };
  };
  config = mkIf (config.defaultConfigs.hyprpaper.enable) {
    xdg.configFile."hypr/hyprpaper.conf".text = ''
      preload = ${wallpaper}
      wallpaper = ,${wallpaper}
    '';
  };
}
