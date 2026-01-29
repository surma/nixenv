{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;
  cfg = config.defaultConfigs.opencode.llmProxy;

  # Wrapped opencode that reads the API key from file, fetches models, and sets the env vars
  wrappedOpencode = pkgs.writeScriptBin "opencode" ''
    #!${pkgs.nushell}/bin/nu
    def --wrapped main [...args] {
      # Ensure models.json exists to prevent startup crash
      let cache_dir = $"($env.HOME)/.cache/opencode"
      mkdir $cache_dir
      let models_file = $"($cache_dir)/models.json"
      
      # Download models.json if it doesn't exist or is empty
      if not ($models_file | path exists) or (($models_file | path exists) and (open $models_file | is-empty)) {
        try {
          http get "https://models.dev/api.json" | save --force $models_file
        } catch {
          # If download fails, create empty JSON object so OpenCode can handle it
          "{}" | save --force $models_file
        }
      }

      # Read API key
      let api_key = (open ${cfg.apiKeyFile} | str trim)
      
      # Fetch models with metadata from proxy
      let models_response = http get --full --headers [
        "Authorization" $"Bearer ($api_key)"
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
      
      # Build dynamic config with ALL provider configurations
      let dynamic_config = {
        model: "anthropic/claude-sonnet-4-5",
        provider: {
          "llm.surma.technology": {
            name: "LLM Proxy",
            npm: "@ai-sdk/openai-compatible",
            models: $models_config,
            options: {
              baseURL: "${cfg.baseURL}",
              apiKey: $api_key
            }
          },
          anthropic: {
            name: "Anthropic",
            npm: "@ai-sdk/anthropic",
            options: {
              baseURL: "https://vendors.llm.surma.technology/anthropic/v1",
              apiKey: $api_key
            }
          },
          openai: {
            name: "OpenAI",
            npm: "@ai-sdk/openai",
            options: {
              baseURL: "https://vendors.llm.surma.technology/openai/v1",
              apiKey: $api_key
            }
          },
          google: {
            name: "Google",
            npm: "@ai-sdk/google",
            options: {
              baseURL: "https://vendors.llm.surma.technology/googlevertexai-global/v1beta1/projects/shopify-ml-production/locations/global/publishers/google",
              headers: {
                Authorization: $"Bearer ($api_key)"
              }
            }
          },
          groq: {
            name: "Groq",
            npm: "@ai-sdk/groq",
            options: {
              baseURL: "https://vendors.llm.surma.technology/groq/openai/v1",
              apiKey: $api_key
            }
          },
          xai: {
            name: "xAI",
            npm: "@ai-sdk/xai",
            options: {
              baseURL: "https://vendors.llm.surma.technology/xai/v1",
              apiKey: $api_key
            }
          },
          cohere: {
            name: "Cohere",
            npm: "@ai-sdk/cohere",
            options: {
              baseURL: "https://vendors.llm.surma.technology/cohere/v2",
              apiKey: $api_key
            }
          },
          perplexity: {
            name: "Perplexity",
            npm: "@ai-sdk/perplexity",
            options: {
              baseURL: "https://vendors.llm.surma.technology/perplexity",
              apiKey: $api_key
            }
          }
        },
        enabled_providers: [
          "llm.surma.technology",
          "anthropic",
          "openai",
          "google",
          "groq",
          "xai",
          "cohere",
          "perplexity"
        ]
      }
      
      # Set config content env var
      $env.OPENCODE_CONFIG_CONTENT = ($dynamic_config | to json)
      
      # Execute opencode
      let opencode_bin = ($env.OPENCODE_PATH? | default "${pkgs.opencode}/bin/opencode")
      exec $opencode_bin ...$args
    }
  '';
in
with lib;
{

  imports = [
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
      programs.mcp-playwright.enable = mkIf isEnabled true;
      secrets.items.llm-proxy-client-key.target = mkDefault "${config.home.homeDirectory}/.local/state/opencode/api-key";
      programs.opencode = {
        plugins = {
          "notification.js" = builtins.readFile ./plugin/notification.js;
        };
        extraConfig = {
          # model and provider config will be injected via OPENCODE_CONFIG_CONTENT
        };
        mcps = {
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
