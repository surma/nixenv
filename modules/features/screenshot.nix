{
  config,
  pkgs,
  lib,
  systemManager,
  ...
}:
let
  # Like niri's screenshot action: select an area, save it to the same file
  # as niri, and copy it to the clipboard.
  sxwmScreenshot = pkgs.writeShellApplication {
    name = "sxwm-screenshot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
    ];
    text = ''
      area="$(slurp)"
      grim -g "$area" - | tee "$HOME/Downloads/screenshot.png" | wl-copy --type image/png
    '';
  };
  screenshotHelper = pkgs.makeDesktopItem {
    name = "screenshot";
    desktopName = "Take screenshot";
    exec =
      if config.defaultConfigs.sxwm.enable then
        lib.getExe sxwmScreenshot
      else if config.defaultConfigs.niri.enable then
        "${pkgs.niri}/bin/niri msg action screenshot"
      else
        "${pkgs.grimblast}/bin/grimblast save area ${config.home.homeDirectory}/Downloads/screenshot.png";
  };
in
{
  # Screenshot tools are Linux-only (Wayland)
  config = lib.mkIf (systemManager == "home-manager" && pkgs.stdenv.isLinux) {
    home.packages = with pkgs; [
      grimblast
      screenshotHelper
    ];

    defaultConfigs.niri.extraConfig = lib.mkIf config.defaultConfigs.niri.enable ''
      screenshot-path "~/Downloads/screenshot.png"
    '';
  };
}
