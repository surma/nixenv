{ config, pkgs, ... }:
{
  imports = [

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/linux.nix
  ];
  home.packages = (with pkgs; [ ]);

  home.stateVersion = "24.05";
}
