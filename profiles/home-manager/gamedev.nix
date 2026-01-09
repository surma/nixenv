{
  config,
  pkgs,
  lib,
  ...
}:
{
  # allowedUnfreeApps = [ "aseprite" ];
  home.packages = with pkgs; [
    # ldtk
    # aseprite
  ];
}
