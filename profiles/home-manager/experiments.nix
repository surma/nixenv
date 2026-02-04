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
  home.packages =
    (with pkgs; [
      # kdePackages.kdenlive
      # ansel
    ])
    ++ [
    ];
}
