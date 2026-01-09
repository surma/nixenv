{ config, pkgs, ... }:
{
  imports = [

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/linux.nix
  ];
  home.packages = (with pkgs; [ ]);

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#generic-linux";
}
