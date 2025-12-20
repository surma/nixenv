{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;

  models = import ../../overlays/extra-pkgs/opencode/models.nix;
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
        provider = {
          shopify = {
            name = "Shopify";
            npm = "@ai-sdk/openai-compatible";
            options = {
              # apiKey = "{env:SHOPIFY_API_KEY}";
              baseURL = "http://localhost:4000/v1";
            };
            models =
              models
              |> map (name: {
                inherit name;
                value = { inherit name; };
              })
              |> lib.listToAttrs;
          };
        };
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
