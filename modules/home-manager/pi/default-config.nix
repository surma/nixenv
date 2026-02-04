{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  isEnabled = config.defaultConfigs.pi.enable;
  cfg = config.defaultConfigs.pi.llmProxy;

  models = {
    providers = {
      anthropic = {
        baseUrl = "${cfg.vendorBaseURL}/anthropic";
        apiKey = "PI_PROXY_API_KEY";
      };
      openai = {
        baseUrl = "${cfg.vendorBaseURL}/openai/v1";
        apiKey = "PI_PROXY_API_KEY";
      };
      google = {
        baseUrl = "${cfg.vendorBaseURL}/googlevertexai-global/v1beta1/projects/shopify-ml-production/locations/global/publishers/google";
        apiKey = "PI_PROXY_API_KEY";
        headers = {
          Authorization = "PI_PROXY_AUTH_HEADER";
        };
      };
      groq = {
        baseUrl = "${cfg.vendorBaseURL}/groq/openai/v1";
        apiKey = "PI_PROXY_API_KEY";
      };
      xai = {
        baseUrl = "${cfg.vendorBaseURL}/xai/v1";
        apiKey = "PI_PROXY_API_KEY";
      };
    };
  };

  wrapper = pkgs.writeShellScriptBin "pi" ''
    if [ -f "${cfg.apiKeyFile}" ]; then
      export PI_PROXY_API_KEY="$(tr -d '\n' < "${cfg.apiKeyFile}")"
    fi

    if [ -n "''${PI_PROXY_API_KEY:-}" ]; then
      export PI_PROXY_AUTH_HEADER="Bearer ''${PI_PROXY_API_KEY}"
    fi

    export PI_SKIP_VERSION_CHECK=1

    exec ${inputs.self.packages.${pkgs.system}.pi-coding-agent}/bin/pi "$@"
  '';
in
with lib;
{
  options = {
    defaultConfigs.pi = {
      enable = mkEnableOption "";

      llmProxy = {
        vendorBaseURL = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology";
          description = "Base URL for vendor routes on the LLM proxy";
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
      secrets.items.llm-proxy-client-key.target = mkDefault "${config.home.homeDirectory}/.local/state/pi/api-key";

      programs.pi = mkIf isEnabled {
        enable = true;
      };

      home.file = mkIf isEnabled {
        ".pi/agent/models.json".text = builtins.toJSON models;
      };
    }

    (mkIf (isEnabled && cfg.apiKeyFile != null) {
      programs.pi.package = wrapper;
    })
  ];
}
