{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;
  cfg = config.defaultConfigs.opencode.llmProxy;

  models = import ../../overlays/extra-pkgs/opencode/models.nix;

  # Build options object conditionally
  providerOptions = {
    baseURL = cfg.baseURL;
  }
  // lib.optionalAttrs (cfg.apiKeyFile != null) {
    apiKey = "{env:LLM_PROXY_API_KEY}";
  };

  # Wrapped opencode that reads the API key from file and sets the env var
  wrappedOpencode = pkgs.writeScriptBin "opencode" ''
    #!${pkgs.nushell}/bin/nu
    def --wrapped main [...args] {
      $env.LLM_PROXY_API_KEY = (open ${cfg.apiKeyFile} | str trim)
      exec ${pkgs.opencode}/bin/opencode ...$args
    }
  '';
in
with lib;
{

  imports = [
    ../mcp-nixos.nix
    ../mcp-playwright.nix
  ];

  options = {
    defaultConfigs.opencode = {
      enable = mkEnableOption "";

      llmProxy = {
        baseURL = mkOption {
          type = types.str;
          default = "https://proxy.llm.surma.technology/v1";
          description = "Base URL for the LLM proxy";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = config.secrets.items.llm-proxy-client-key.target;
          description = "Path to file containing the API key for the LLM proxy";
        };
      };
    };
  };

  config = mkMerge [
    {
      customScripts.noti.enable = mkIf isEnabled true;
      programs.mcp-nixos.enable = mkIf isEnabled true;
      programs.mcp-playwright.enable = mkIf isEnabled true;
      programs.opencode = {
        plugins = {
          "notification.js" = builtins.readFile ./plugin/notification.js;
        };
        extraConfig = {
          model = "shopify/shopify:anthropic:claude-sonnet-4-5";
          provider = {
            shopify = {
              name = "Shopify";
              npm = "@ai-sdk/openai-compatible";
              options = providerOptions;
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
    }

    # Use wrapped opencode that reads API key from file when apiKeyFile is set
    (mkIf (cfg.apiKeyFile != null) {
      programs.opencode.package = wrappedOpencode;
    })
  ];
}
