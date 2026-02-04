{ pkgs, config, lib, systemManager, inputs, ... }:
with lib;
{
  options = {
    programs.fetch-mcp = {
      enable = mkEnableOption "fetch MCP server";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.fetch-mcp;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.fetch-mcp.enable) {
    home.packages = [ config.programs.fetch-mcp.package ];
  };
}
