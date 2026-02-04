{
  config,
  lib,
  pkgs,
  systemManager,
  ...
}:
let
  name = "telegram";
  appConfig = config.programs.${name};
in
with lib;
{
  options = {
    programs.${name} = {
      enable = mkEnableOption "Telegram messenger";
      package = mkPackageOption pkgs "telegram-desktop" { };
    };
  };

  config = mkIf appConfig.enable (
    if systemManager == "nixos" || systemManager == "nix-darwin" then
      { environment.systemPackages = [ appConfig.package ]; }
    else if systemManager == "home-manager" then
      { home.packages = [ appConfig.package ]; }
    else
      throw "Unsupported system manager ${systemManager} for telegram"
  );
}
