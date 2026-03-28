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

  defaultSettings = {
    defaultProvider = "openai";
    defaultModel = "gpt-5.4";
    defaultThinkingLevel = "high";
    packages = [ "ssh://git@github.com/surma/pi-config" ];
    theme = "gruvbox-dark-medium";
  };

  settings = lib.recursiveUpdate defaultSettings piCfg.settings;

  wrapper = pkgs.writeShellScriptBin "pi" ''
    if [ -f "${llmProxyCfg.apiKeyFile}" ]; then
      export PI_PROXY_API_KEY="$(tr -d '\n' < "${llmProxyCfg.apiKeyFile}")"
    fi

    if [ -n "''${PI_PROXY_API_KEY:-}" ]; then
      export PI_PROXY_AUTH_HEADER="Bearer ''${PI_PROXY_API_KEY}"
    fi

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
    };
  };

  config = mkMerge [
    {
      programs.pi = mkIf isEnabled {
        enable = true;
      };

      home.file = mkIf isEnabled {
        ".pi/agent/settings.json" = {
          text = builtins.toJSON settings;
          mutable = true;
        };
      };
    }

    (mkIf (isEnabled && llmProxyCfg.apiKeyFile != null) {
      programs.pi.package = wrapper;
    })
  ];
}
