{
  pkgs,
  lib,
  inputs,
  ...
}:
# My terminal, on every machine that I sit at. The font size stays with the
# machine, because it depends on the display.
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.wezterm = {
    enable = true;
    package = pkgs-unstable.wezterm;
  }
  # The module defaults describe macOS. On Linux the WebGpu frontend is
  # unreliable, the compositor draws the window frame, and nothing reports
  # the system appearance, so the theme needs a name.
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    frontend = "OpenGL";
    theme = "dark";
    window-decorations = null;
  };

  defaultConfigs.wezterm.enable = true;
}
