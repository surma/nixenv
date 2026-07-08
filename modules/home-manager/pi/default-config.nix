{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  isEnabled = config.defaultConfigs.pi.enable;
  piCfg = config.defaultConfigs.pi;
  llmProxyCfg = piCfg.llmProxy;
  openRouterCfg = piCfg.openRouter;
  proxyExtensionCfg = piCfg.extensions.proxy;
  mcpAdapterCfg = piCfg.packages.mcpAdapter;

  defaultSettings = {
    defaultProvider = "anthropic";
    defaultModel = "claude-opus-4-8";
    defaultThinkingLevel = "xhigh";
    steeringMode = "all";
    compaction = {
      enabled = true;
       reserveTokens = 50000;
    };
    packages = [
      {
        source = "ssh://git@github.com/surma/pi-config";
        extensions = [ "-extensions/proxy.ts" ];
        prompts = [ ];
      }
    ];
    theme = "gruvbox-dark-medium";
  };

  settings =
    let
      mergedSettings = lib.recursiveUpdate defaultSettings piCfg.settings;
      extraPackages =
        lib.optional mcpAdapterCfg.enable "npm:pi-mcp-adapter"
        ++ piCfg.extraPackages;
    in
    mergedSettings
    // lib.optionalAttrs (extraPackages != [ ]) {
      packages = (mergedSettings.packages or [ ]) ++ extraPackages;
    };

  wrapper = pkgs.writeShellScriptBin "pi" ''
    ${lib.optionalString (llmProxyCfg.apiKeyFile != null) ''
      if [ -f "${llmProxyCfg.apiKeyFile}" ]; then
        export PI_PROXY_API_KEY="$(tr -d '\n' < "${llmProxyCfg.apiKeyFile}")"
      fi

      if [ -n "''${PI_PROXY_API_KEY:-}" ]; then
        export PI_PROXY_AUTH_HEADER="Bearer ''${PI_PROXY_API_KEY}"
      fi
    ''}

    ${lib.optionalString (openRouterCfg.keyFile != null) ''
      if [ -f "${openRouterCfg.keyFile}" ]; then
        export OPENROUTER_API_KEY="$(tr -d '\n' < "${openRouterCfg.keyFile}")"
      fi
    ''}

    export PI_PROXY_BASE_URL=${lib.escapeShellArg llmProxyCfg.vendorBaseURL}
    export PI_SKIP_VERSION_CHECK=1

    exec ${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-coding-agent}/bin/pi "$@"
  '';
in
with lib;
{
  options = {
    defaultConfigs.pi = {
      enable = mkEnableOption "";

      settings = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional Pi settings merged into ~/.pi/agent/settings.json";
      };

      extraPackages = mkOption {
        type = types.listOf (types.either types.str (types.attrsOf types.anything));
        default = [ ];
        description = "Extra Pi packages concatenated into settings.json packages. Merges across modules.";
      };

      llmProxy = {
        vendorBaseURL = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology";
          description = "Base URL for Shopify proxy passthrough routes";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = lib.attrByPath [ "secrets" "items" "llm-proxy-client-key" "target" ] null config;
          description = "Path to file containing the API key for the LLM proxy";
        };
      };

      openRouter.keyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing the OpenRouter API key";
      };

      extensions.proxy.enable = mkEnableOption "the machine-local Pi proxy extension";

      extensions.dotenv.enable = mkEnableOption "the dotenv extension (loads .env from cwd + HM session vars)";

      extensions.contextUsage.enable = mkEnableOption "the context-usage awareness extension (injects usage warnings into prompts)";

      packages.mcpAdapter.enable = mkEnableOption "the pi-mcp-adapter Pi package";

      mcpConfig = mkOption {
        type = types.nullOr (types.attrsOf types.anything);
        default = null;
        description = "JSON content written to ~/.pi/agent/mcp.json";
      };
    };
  };

  config = mkMerge [
    {
      programs.pi = mkIf isEnabled {
        enable = true;
      };

      home.file = mkIf isEnabled (
        {
          ".pi/agent/settings.json" = {
            text = builtins.toJSON settings;
            mutable = true;
          };
          ".pi/agent/APPEND_SYSTEM.md".source = ../../../assets/pi/APPEND_SYSTEM.md;
        }
        // optionalAttrs (piCfg.mcpConfig != null) {
          ".pi/agent/mcp.json" = {
            text = builtins.toJSON piCfg.mcpConfig;
            mutable = true;
          };
        }
        // optionalAttrs proxyExtensionCfg.enable {
          ".pi/agent/extensions/proxy.ts" = {
            source = ./extension/proxy.ts;
            force = true;
          };
        }
        // optionalAttrs piCfg.extensions.dotenv.enable {
          ".pi/agent/extensions/dotenv.ts".source = ./extension/dotenv.ts;
        }
        // optionalAttrs piCfg.extensions.contextUsage.enable {
          ".pi/agent/extensions/context-usage.ts".source = ./extension/context-usage.ts;
        }
      );
    }

    (mkIf (isEnabled && (llmProxyCfg.apiKeyFile != null || openRouterCfg.keyFile != null || proxyExtensionCfg.enable)) {
      programs.pi.package = wrapper;
    })
  ];
}
