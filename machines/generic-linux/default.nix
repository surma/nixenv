{ config, pkgs, ... }:
{
  imports = [

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/roles/dev.nix
    ../../profiles/home-manager/platform/linux.nix
  ];
  home.packages = (with pkgs; [ ]);

  home.stateVersion = "24.05";
}
