{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/dev.nix
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";
  secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";
  secrets.items.llm-proxy-openclaw-env.command = ''
    mkdir -p ${config.home.homeDirectory}/.local/state/openclaw
    key="$(cat)"
    cat > ${config.home.homeDirectory}/.local/state/openclaw/llm-proxy.env <<EOF
LLM_PROXY_API_KEY=$key
PI_PROXY_API_KEY=$key
PI_PROXY_AUTH_HEADER=Bearer $key
OPENAI_API_KEY=$key
ANTHROPIC_API_KEY=$key
GEMINI_API_KEY=$key
GOOGLE_API_KEY=$key
GROQ_API_KEY=$key
XAI_API_KEY=$key
EOF
    chmod 600 ${config.home.homeDirectory}/.local/state/openclaw/llm-proxy.env
  '';
  secrets.items.openclaw-telegram-token.target = "${config.home.homeDirectory}/.local/state/openclaw/telegram-token";
  secrets.items.openclaw-gateway-token.command = ''
    mkdir -p ${config.home.homeDirectory}/.local/state/openclaw
    token="$(cat)"
    if [ "''${token#OPENCLAW_GATEWAY_TOKEN=}" != "$token" ]; then
      token="''${token#OPENCLAW_GATEWAY_TOKEN=}"
    fi
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$token" > ${config.home.homeDirectory}/.local/state/openclaw/gateway-token.env
    chmod 600 ${config.home.homeDirectory}/.local/state/openclaw/gateway-token.env
  '';

  nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

  home.stateVersion = "25.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#scout";

  # Best-effort linger enablement for user services to survive logout.
  home.activation.enableLinger = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if command -v loginctl >/dev/null 2>&1; then
      if [ "$(loginctl show-user ${config.home.username} --property=Linger --value 2>/dev/null || true)" != "yes" ]; then
        loginctl enable-linger ${config.home.username} >/dev/null 2>&1 || true
      fi
    fi
  '';

  programs.openclaw = {
    enable = true;
    toolNames =
      (builtins.filter (name: name != "nodejs_22") pkgs.openclawPackages.toolNames)
      ++ [ "nodejs_24" ];
    instances.default.configPath = "${config.home.homeDirectory}/.openclaw/openclaw.hm.json";
    instances.default.config = config.programs.openclaw.config;
    config = {
      gateway = {
        mode = "local";
        auth = {
          mode = "token";
          token = {
            source = "env";
            provider = "default";
            id = "OPENCLAW_GATEWAY_TOKEN";
          };
        };
      };

      env.vars = {
        OPENAI_BASE_URL = "https://vendors.llm.surma.technology/openai/v1";
        ANTHROPIC_BASE_URL = "https://vendors.llm.surma.technology/anthropic";
        GEMINI_BASE_URL = "https://vendors.llm.surma.technology/googlevertexai-global/v1beta1/projects/shopify-ml-production/locations/global/publishers/google";
        GROQ_BASE_URL = "https://vendors.llm.surma.technology/groq/openai/v1";
        XAI_BASE_URL = "https://vendors.llm.surma.technology/xai/v1";
      };

      secrets.providers.default = {
        source = "env";
        allowlist = [
          "LLM_PROXY_API_KEY"
          "OPENCLAW_GATEWAY_TOKEN"
        ];
      };

      agents.defaults.model.primary = "openai/gpt-5-mini";

      channels.telegram = {
        tokenFile = config.secrets.items.openclaw-telegram-token.target;
        allowFrom = [ 5248021986 ];
        groups."*".requireMention = true;
      };
    };

    bundledPlugins.goplaces.enable = false;
  };

  home.file.".openclaw/openclaw.hm.json".force = true;

  home.activation.openclawMergeManagedConfig = lib.hm.dag.entryAfter [ "openclawConfigFiles" ] ''
    managed="${config.home.homeDirectory}/.openclaw/openclaw.hm.json"
    merged="${config.home.homeDirectory}/.openclaw/openclaw.json"
    tmp="$merged.tmp"

    if [ ! -f "$managed" ]; then
      exit 0
    fi

    if [ -f "$merged" ] && ${pkgs.jq}/bin/jq -e . "$merged" >/dev/null 2>&1; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$merged" "$managed" > "$tmp"
    else
      ${pkgs.coreutils}/bin/cp "$managed" "$tmp"
    fi

    ${pkgs.coreutils}/bin/mv "$tmp" "$merged"
  '';

  systemd.user.services.openclaw-gateway.Install.WantedBy = [ "default.target" ];
  systemd.user.services.openclaw-gateway.Service.Environment = lib.mkAfter [
    "OPENCLAW_CONFIG_PATH=${config.home.homeDirectory}/.openclaw/openclaw.json"
  ];
  systemd.user.services.openclaw-gateway.Service.EnvironmentFile = [
    "${config.home.homeDirectory}/.local/state/openclaw/gateway-token.env"
    "${config.home.homeDirectory}/.local/state/openclaw/llm-proxy.env"
  ];

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
}
