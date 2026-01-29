{ pkgs, config, lib, systemManager, ... }:
with lib;
{
  options = {
    programs.mcp-nixos = {
      enable = mkEnableOption "mcp-nixos server";
      package = mkOption {
        type = types.package;
        default = pkgs.mcp-nixos;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.mcp-nixos.enable) {
    home.packages = [ config.programs.mcp-nixos.package ];
  };
}
