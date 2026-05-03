{
  config,
  lib,
  pkgs,
  inputs,
  systemManager,
  ...
}:
let
  name = "telegram";
  appConfig = config.programs.${name};
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
with lib;
{
  options = {
    programs.${name} = {
      enable = mkEnableOption "Telegram messenger";
      package = mkOption {
        type = types.package;
        default = pkgs-unstable.telegram-desktop;
        defaultText = literalExpression "inputs.nixpkgs-unstable.legacyPackages.\${system}.telegram-desktop";
        description = "Telegram Desktop package (defaults to nixpkgs-unstable for a newer version).";
      };
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
