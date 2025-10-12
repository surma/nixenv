{ config, pkgs, ... }:
{
  imports = [

    ../home-manager/base.nix
    ../home-manager/dev.nix
    ../home-manager/linux.nix
  ];
  home.packages = (with pkgs; [ ]);

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#generic-linux";
}
