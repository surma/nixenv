{
  pkgs,
  config,
  lib,
  systemManager,
  ...
}:
let
  name = "obs";
  caskName = "obs";
  package = pkgs.obs-studio;
in
with lib;
{
  options = {
    programs.${name}.enable = mkEnableOption "OBS Studio";
  };

  config = mkIf config.programs.${name}.enable (
    if systemManager == "nix-darwin" then
      { homebrew.casks = [ caskName ]; }
    else if systemManager == "nixos" then
      { environment.systemPackages = [ package ]; }
    else if systemManager == "home-manager" then
      { home.packages = [ package ]; }
    else
      throw "Unsupported system manager ${systemManager} for obs"
  );
}
