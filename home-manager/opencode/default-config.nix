{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;
in
with lib;
{
  imports = [
    ../mcp-nixos.nix
    ../mcp-playwright.nix
  ];

  options = {
    defaultConfigs.opencode.enable = mkEnableOption "";
  };

  config = {

    programs.mcp-nixos.enable = mkIf isEnabled true;
    programs.mcp-playwright.enable = mkIf isEnabled true;
    programs.opencode = {
      extraConfig = {
        # provider = {
        #   litellm = {
        #     models = {
        #       "shopify:anthropic:claude-sonnet-4" = { };
        #       "shopify:google:gemini-2.5-pro-preview-05-06" = { };
        #     };
        #     npm = "@ai-sdk/openai-compatible";
        #     options = {
        #       baseURL = "http://litellm.surmcluster.10.0.0.2.nip.io";
        #     };
        #   };
        # };

      };
      mcps = {
        mcp-nixos = {
          type = "local";
          command = [ "mcp-nixos" ];
        };
        mcp-playwright = {
          type = "local";
          command = [ "mcp-playwright" ];
        };
      };
    };
  };
}
