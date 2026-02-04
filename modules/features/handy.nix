{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  cfg = config.programs.handy;
in
{
  imports = [
    ../home-manager/handy/default-config.nix
  ];

  options = {
    programs.handy = {
      enable = mkEnableOption "Handy speech-to-text tool";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.handy;
        description = "The handy package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];
  };
}
