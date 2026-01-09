{
  config,
  pkgs,
  lib,
  ...
}:
let
  screenshotHelper = pkgs.makeDesktopItem {
    name = "screenshot";
    desktopName = "Take screenshot";
    exec = "${pkgs.grimblast}/bin/grimblast save area ${config.home.homeDirectory}/Downloads/screenshot.png";
  };
in
{

  home.packages = (
    with pkgs;
    [
      grimblast
      screenshotHelper
    ]
  );
}
