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
  proxyExtensionCfg = piCfg.extensions.proxy;
  mcpAdapterCfg = piCfg.packages.mcpAdapter;

  defaultSettings = {
    defaultProvider = "openai";
    defaultModel = "gpt-5.4";
    defaultThinkingLevel = "high";
    packages = [
      {
        source = "ssh://git@github.com/surma/pi-config";
        extensions = [ "-extensions/proxy.ts" ];
      }
    ];
    skills = lib.optional config.programs.agent-browser.enable "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser}/share/pi/skills/agent-browser";
    theme = "gruvbox-dark-medium";
  };

  settings =
    let
      mergedSettings = lib.recursiveUpdate defaultSettings piCfg.settings;
    in
    mergedSettings
    // lib.optionalAttrs mcpAdapterCfg.enable {
      packages = (mergedSettings.packages or [ ]) ++ [ "npm:pi-mcp-adapter" ];
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

      extensions.proxy.enable = mkEnableOption "the machine-local Pi proxy extension";

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
        }
        // optionalAttrs (piCfg.mcpConfig != null) {
          ".pi/agent/mcp.json" = {
            text = builtins.toJSON piCfg.mcpConfig;
            mutable = true;
          };
        }
        // optionalAttrs proxyExtensionCfg.enable {
          ".pi/agent/extensions/proxy.ts".source = ./extension/proxy.ts;
        }
      );
    }

    (mkIf (isEnabled && (llmProxyCfg.apiKeyFile != null || proxyExtensionCfg.enable)) {
      programs.pi.package = wrapper;
    })
  ];
}
