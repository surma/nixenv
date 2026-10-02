{
  config,
  pkgs,
  lib,
  systemManager,
  ...
}:
let
  screenshotHelper = pkgs.makeDesktopItem {
    name = "screenshot";
    desktopName = "Take screenshot";
    exec =
      if config.defaultConfigs.niri.enable then
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
