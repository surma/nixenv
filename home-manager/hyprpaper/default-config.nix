{
  pkgs,
  config,
  lib,
  ...
}:
let
  src = ../../assets/wallpapers;
  wallpapers = builtins.readDir src;
  defaultWallpaper = wallpapers |> lib.attrNames |> (l: lib.elemAt l 0);
  defaultWallpaperPath = "${src}/${defaultWallpaper}";
in
with lib;
{
  options = {
    defaultConfigs.hyprpaper = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.hyprpaper.enable) {
    xdg.configFile."hypr/hyprpaper.conf".text = ''
      preload = ${defaultWallpaperPath}
      wallpaper = ,${defaultWallpaperPath}
    '';
  };
}
