{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) callPackage;
in
{
  home.packages = (
    with pkgs;
    [
      qmk
      # openocd
      dfu-util
      gdb
    ]
  );
}
