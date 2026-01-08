{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkMultiSystemModule = import ../../lib/mk-multi-system-module.nix;

  name = "obsidian";
  caskName = "obsidian";
  package = pkgs.obsidian;

  mod = mkMultiSystemModule name rec {
    nix-darwin = {
      homebrew.casks = lib.optionals config.programs.${name}.enable [ caskName ];
    };
    nixos = {
      environment.systemPackages = lib.optionals config.programs.${name}.enable [ package ];
    };
    home-manager = {
      home.packages = lib.optionals config.programs.${name}.enable [ package ];
    };
    system-manager = nixos;
  };
in
with lib;
{
  imports = [ mod ];
  options = {
    programs.${name}.enable = mkEnableOption "";
  };
}
