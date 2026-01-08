{
  config,
  pkgs,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    nixfmt-rfc-style
    nixd
  ];
}
