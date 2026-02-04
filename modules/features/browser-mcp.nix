{ pkgs, config, lib, systemManager, inputs, ... }:
with lib;
{
  options = {
    programs.browser-mcp = {
      enable = mkEnableOption "browser MCP server";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.browser-mcp;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.browser-mcp.enable) {
    home.packages = [ config.programs.browser-mcp.package ];
  };
}
