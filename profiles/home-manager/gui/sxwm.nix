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
  # swaybg centers in output-buffer pixels, so keep the logo at its exact 795x360 size.
  sxWallpaper = pkgs.runCommand "sx-wallpaper.png" {
    nativeBuildInputs = [ pkgs.resvg ];
  } ''
    resvg --width 795 --height 360 ${inputs.sx}/assets/logo/sx-plate.svg "$out"
  '';
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
      Service.ExecStart = "${lib.getExe pkgs.swaybg} -i ${sxWallpaper} -m center -c '${sxPalette.bone}'";
    };
  };
}
