{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
{
  options = {
    programs.qmd = {
      enable = mkEnableOption "Pi";
      package = mkOption {
        type = types.package;
        default = inputs.qmd.packages.${pkgs.stdenv.hostPlatform.system}.qmd;
        description = "Query Markdown Documents";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.qmd.enable) {
    home.packages = [ config.programs.qmd.package ];
  };
}

