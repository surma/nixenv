{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../../profiles/home-manager/minimal.nix
    ../../modules/home-manager/ssh-keys
    ../../modules/home-manager/gpg-keys
  ];

  config = {
    home.packages = (
      with pkgs;
      [
      ]
    );

    home.stateVersion = "25.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#pylon";
  };
}
