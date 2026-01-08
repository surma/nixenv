{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.claude-code.enable;
in
with lib;
{
  imports = [
    ../fetch-mcp
    ../browser-mcp
    ../mcp-nixos
  ];

  options = {
    defaultConfigs.claude-code.enable = mkEnableOption "";
  };

  config = {
    programs.fetch-mcp.enable = mkIf isEnabled true;
    programs.browser-mcp.enable = mkIf isEnabled true;
    programs.mcp-nixos.enable = mkIf isEnabled true;
    programs.claude-code = mkIf isEnabled {
      enable = true;
      overrides.baseURL = "https://proxy.shopify.ai/vendors/anthropic-claude-code";
      mcps = {
        fetch-mcp = {
          type = "stdio";
          command = [ "fetch-mcp" ];
        };
        browser-mcp = {
          type = "stdio";
          command = [ "browser-mcp" ];
        };
        mcp-nixos = {
          type = "stdio";
          command = [ "mcp-nixos" ];
        };
      };
    };
  };
}
