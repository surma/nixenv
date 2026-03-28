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
  cfg = config.programs.web-search-cli;
in
{
  imports = [
    ../home-manager/web-search-cli/default-config.nix
  ];

  options = {
    programs.web-search-cli = {
      enable = mkEnableOption "web-search-cli";
      package = mkOption {
        type = types.package;
        default = inputs.web-search-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
        description = "The web-search-cli package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];
  };
}
