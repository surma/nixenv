{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;
  cfg = config.defaultConfigs.opencode.llmProxy;

  # Build options object conditionally
  providerOptions = {
    baseURL = cfg.baseURL;
  }
  // lib.optionalAttrs (cfg.apiKeyFile != null) {
    apiKey = "{env:LLM_PROXY_API_KEY}";
  };

  # Wrapped opencode that reads the API key from file, fetches models, and sets the env vars
  wrappedOpencode = pkgs.writeScriptBin "opencode" ''
    #!${pkgs.nushell}/bin/nu
    def --wrapped main [...args] {
      # Read API key
      $env.LLM_PROXY_API_KEY = (open ${cfg.apiKeyFile} | str trim)
      
      # Fetch models from proxy
      let models_response = http get --full --headers [
        "Authorization" $"Bearer ($env.LLM_PROXY_API_KEY)"
      ] "${cfg.baseURL}/models"
      
      # Extract model IDs
      let model_ids = $models_response 
        | get body.data 
        | get id
      
      # Generate models config
      let models_config = $model_ids 
        | each {|id| {name: $id, value: {name: $id}}} 
        | transpose -r -d 
        | into record
      
      # Build dynamic config
      let dynamic_config = {
        provider: {
          "llm.surma.technology": {
            models: $models_config
          }
        }
      }
      
      # Set config content env var
      $env.OPENCODE_CONFIG_CONTENT = ($dynamic_config | to json)
      
      # Execute opencode
      exec ${pkgs.opencode}/bin/opencode ...$args
    }
  '';
in
with lib;
{

  imports = [
    ../mcp-nixos
    ../mcp-playwright
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
          model = "llm.surma.technology/shopify:anthropic:claude-sonnet-4-5";
          provider = {
            "llm.surma.technology" = {
              name = "LLM Proxy";
              npm = "@ai-sdk/openai-compatible";
              options = providerOptions;
              # models will be injected dynamically via OPENCODE_CONFIG_CONTENT
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
