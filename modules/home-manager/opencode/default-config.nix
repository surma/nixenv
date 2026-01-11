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
      
      # Fetch models with metadata from proxy
      let models_response = http get --full --headers [
        "Authorization" $"Bearer ($env.LLM_PROXY_API_KEY)"
      ] "${cfg.baseURL}/model/info"
      
      # Extract models with metadata
      let models_data = $models_response | get body.data
      
      # Generate models config with limit information
      let models_config = $models_data
        | each {|m|
          let model_id = $m.model_name
          
          # Build base model config
          mut model_config = {
            id: $model_id
            name: $model_id
          }
          
          # Add limit info if model_info exists and has the required fields
          if ($m | get -o model_info) != null {
            let info = $m.model_info
            let max_input = $info | get -o max_input_tokens
            let max_output = $info | get -o max_output_tokens
            
            # Only add limit if both fields are present and not null
            if $max_input != null and $max_output != null {
              $model_config = $model_config | insert limit {
                context: $max_input
                output: $max_output
              }
            }
          }
          
          {name: $model_id, value: $model_config}
        }
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
      secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/opencode/api-key";
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
