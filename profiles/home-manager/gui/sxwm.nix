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

    # hyprlock's fade animations capture the screen with wlr-screencopy, which
    # SXWM does not implement yet. hyprlock 0.9.6 then crashes instead of
    # locking, so turn the animations off.
    programs.hyprlock.settings.animations.enabled = false;

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
