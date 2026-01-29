{ pkgs, config, lib, systemManager, ... }:
with lib;
{
  options = {
    programs.browser-mcp = {
      enable = mkEnableOption "browser MCP server";
      package = mkOption {
        type = types.package;
        default = pkgs.browser-mcp;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.browser-mcp.enable) {
    home.packages = [ config.programs.browser-mcp.package ];
  };
}
