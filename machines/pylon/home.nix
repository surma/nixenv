{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/platform/linux.nix
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
  };
}
