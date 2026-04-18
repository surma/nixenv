{
  pkgs,
  config,
  lib,
  inputs,
  options,
  ...
}:
let
  isEnabled = config.defaultConfigs.opencode.enable;
  cfg = config.defaultConfigs.opencode.llmProxy;
  defaultApiKeyPath = "${config.home.homeDirectory}/.local/state/opencode/api-key";

  # Wrapped opencode that reads the API key from file and exports proxy env vars.
  wrappedOpencode = pkgs.writeScriptBin "opencode" ''
    #!${pkgs.nushell}/bin/nu
    def --wrapped main [...args] {
      # Ensure models.json exists to prevent startup crash.
      let cache_dir = $"($env.HOME)/.cache/opencode"
      mkdir $cache_dir
      let models_file = $"($cache_dir)/models.json"

      if not ($models_file | path exists) or (($models_file | path exists) and (open $models_file | is-empty)) {
        try {
          http get "https://models.dev/api.json" | save --force $models_file
        } catch {
          "{}" | save --force $models_file
        }
      }

      if ($env.OPENCODE_API_KEY? | is-empty) {
        $env.OPENCODE_API_KEY = (open ${cfg.apiKeyFile} | str trim)
      }

      $env.OPENCODE_PROXY_BASE_URL = "${cfg.baseURL}"
      $env.OPENCODE_USAGE_SOURCE = if ($args | is-empty) { "interactive" } else { "cli" }

      let opencode_bin = ($env.OPENCODE_PATH? | default "${
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.opencode
      }/bin/opencode")
      exec $opencode_bin ...$args
    }
  '';
in
with lib;
{

  imports = [
    # MCP servers now globally injected via features
    # ../mcp-playwright
  ];

  options = {
    defaultConfigs.opencode = {
      enable = mkEnableOption "";

      llmProxy = {
        baseURL = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology";
          description = "Base URL for vendor proxy routes";
        };

        manageSecret = mkOption {
          type = types.bool;
          default = true;
          description = "Whether this module should also manage the OpenCode LLM proxy API key secret file.";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = lib.attrByPath [ "secrets" "items" "llm-proxy-client-key" "target" ] null config;
          description = "Path to file containing the API key for the LLM proxy";
        };
      };
    };
  };

  config = mkMerge [
    (
      (lib.optionalAttrs (options ? customScripts) {
        customScripts.noti.enable = mkIf isEnabled true;
      })
      // {
        programs.opencode.enable = mkIf isEnabled true;
        programs.opencode = {
          plugins = {
            "notification.js" = builtins.readFile ./plugin/notification.js;
            "shopify-proxy.js" = builtins.readFile ./plugin/shopify-proxy.js;
            "context-tracker.js" = builtins.readFile ./plugin/context-tracker.js;
          };
          extraConfig = {
            model = "anthropic/claude-sonnet-4-5";
            plugin = [ "file://${config.home.homeDirectory}/.config/opencode/plugin/shopify-proxy.js" ];
          };
        };
      }
    )

    (mkIf (isEnabled && cfg.manageSecret) {
      secrets.items.llm-proxy-client-key.target = mkDefault defaultApiKeyPath;
    })

    # Use wrapped opencode that reads API key from file when apiKeyFile is set
    (mkIf (isEnabled && cfg.apiKeyFile != null) {
      programs.opencode.package = wrappedOpencode;
    })
  ];
}
