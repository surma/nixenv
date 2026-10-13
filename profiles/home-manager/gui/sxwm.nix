{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
# SXWM-specific user settings. ./wayland.nix imports this profile.
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
      Service.ExecStart = "${lib.getExe pkgs.swaybg} -i ${osConfig.gui.wallpaper} -m fill";
    };
  };
}
