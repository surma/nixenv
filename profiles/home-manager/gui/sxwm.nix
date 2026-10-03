{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
# SXWM-specific user settings. ./wayland.nix imports this profile.
let
  wallpapers = ../../../assets/wallpapers;
  defaultWallpaper = builtins.readDir wallpapers |> lib.attrNames |> (names: builtins.head names);
  defaultWallpaperPath = "${wallpapers}/${defaultWallpaper}";
in
{
  config = lib.mkIf (osConfig.gui.compositor == "sxwm") {
    defaultConfigs.sxwm.enable = true;

    systemd.user.services.swaybg = {
      Unit = {
        Description = "Set the default wallpaper";
        PartOf = [ config.wayland.systemd.target ];
        After = [ config.wayland.systemd.target ];
      };
      Install.WantedBy = [ config.wayland.systemd.target ];
      Service.ExecStart = "${lib.getExe pkgs.swaybg} -i ${defaultWallpaperPath} -m fill";
    };
  };
}
