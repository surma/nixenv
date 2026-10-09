{
  config,
  pkgs,
  lib,
  systemManager,
  ...
}:
let
  # Select an area, save it to ~/Downloads/screenshot.png, and copy it to the
  # clipboard. grim works on every compositor that we use.
  screenshot = pkgs.writeShellApplication {
    name = "screenshot";
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
    exec = lib.getExe screenshot;
  };
in
{
  # Screenshot tools are Linux-only (Wayland)
  config = lib.mkIf (systemManager == "home-manager" && pkgs.stdenv.isLinux) {
    home.packages = [ screenshotHelper ];
  };
}
