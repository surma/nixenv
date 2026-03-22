{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
    # ../../profiles/home-manager/cloud.nix
  ];

  config = {
    home.packages = (
      with pkgs;
      [
      ]
    );

    home.stateVersion = "25.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#pylon";

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
  };
}
