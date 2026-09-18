{
  pkgs,
  lib,
  ...
}:
# The fonts that every machine with a screen gets. On Linux fontconfig has to
# know about them, otherwise a font in home.packages stays invisible to every
# application. macOS finds them without fontconfig.
{
  home.packages = with pkgs; [
    fira-code
    roboto
    font-awesome
  ];

  fonts.fontconfig.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;
}
