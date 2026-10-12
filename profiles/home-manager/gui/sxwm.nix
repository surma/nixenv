{
  config,
  osConfig,
  lib,
  pkgs,
  inputs,
  ...
}:
# SXWM-specific user settings. ./wayland.nix imports this profile.
let
  sxPalette = import ../../../lib/sx-palette.nix { inherit inputs; };
  sxWallpaper = ../../../assets/sx/sx-wallpaper-light.png;
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
      Service.ExecStart = "${lib.getExe pkgs.swaybg} -i ${sxWallpaper} -m fit -c '${sxPalette.bone}'";
    };
  };
}
