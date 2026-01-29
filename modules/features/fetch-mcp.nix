{ pkgs, config, lib, systemManager, ... }:
with lib;
{
  options = {
    programs.fetch-mcp = {
      enable = mkEnableOption "fetch MCP server";
      package = mkOption {
        type = types.package;
        default = pkgs.fetch-mcp;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.fetch-mcp.enable) {
    home.packages = [ config.programs.fetch-mcp.package ];
  };
}
