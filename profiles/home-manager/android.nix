{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    home.username = lib.mkDefault "nix-on-droid";
    home.homeDirectory = lib.mkDefault "/data/data/com.termux.nix/files/home";
    home.sessionVariables = {
      CONFIG_MANAGER = "nix-on-droid";
    };

  };
}
