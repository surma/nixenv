{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "telegram";
  pkgName = "telegram-desktop";

  mkMultiSystemModule = import ../../lib/mk-multi-system-module.nix;

  appConfig = config.programs.${name};

  mod = mkMultiSystemModule name rec {
    nixos = {
      environment.systemPackages = lib.optionals appConfig.enable [ appConfig.package ];
    };
    home-manager = {
      home.packages = lib.optionals appConfig.enable [ appConfig.package ];
    };
    system-manager = nixos;
    nixos-darwin = nixos;
  };
in
with lib;
{
  imports = [ mod ];
  options = {
    programs.${name} = {
      enable = mkEnableOption "";
      package = mkPackageOption pkgs pkgName { };
    };
  };
}
