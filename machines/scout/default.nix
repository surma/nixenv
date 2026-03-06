{ config, lib, inputs, ... }:
{
  imports = [
    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
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
GROQ_API_KEY=$key
XAI_API_KEY=$key
EOF
    chmod 600 ${config.home.homeDirectory}/.local/state/openclaw/llm-proxy.env
  '';
  secrets.items.openclaw-telegram-token.target = "${config.home.homeDirectory}/.local/state/openclaw/telegram-token";
  secrets.items.openclaw-gateway-token.command = ''
    mkdir -p ${config.home.homeDirectory}/.local/state/openclaw
    token="$(cat)"
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
    config = {
      gateway = {
        mode = "local";
        auth.mode = "token";
      };

      env.vars = {
        OPENAI_BASE_URL = "https://proxy.llm.surma.technology/v1";
        ANTHROPIC_BASE_URL = "https://vendors.llm.surma.technology/anthropic";
        GROQ_BASE_URL = "https://vendors.llm.surma.technology/groq/openai/v1";
        XAI_BASE_URL = "https://vendors.llm.surma.technology/xai/v1";
      };

      secrets.providers.default = {
        source = "env";
        allowlist = [ "LLM_PROXY_API_KEY" ];
      };

      models = {
        mode = "merge";
        providers.shopify = {
          api = "openai-completions";
          baseUrl = "https://proxy.llm.surma.technology/v1";
          apiKey = {
            source = "env";
            provider = "default";
            id = "LLM_PROXY_API_KEY";
          };
          models = [
            { id = "shopify:openai:gpt-5"; name = "shopify:openai:gpt-5"; }
            { id = "shopify:openai:gpt-5-2025-08-07"; name = "shopify:openai:gpt-5-2025-08-07"; }
            { id = "shopify:openai:gpt-5-mini"; name = "shopify:openai:gpt-5-mini"; }
            { id = "shopify:openai:gpt-5-nano"; name = "shopify:openai:gpt-5-nano"; }
            { id = "shopify:openai:gpt-5.1"; name = "shopify:openai:gpt-5.1"; }
            { id = "shopify:openai:gpt-5.1-2025-11-13"; name = "shopify:openai:gpt-5.1-2025-11-13"; }
            { id = "shopify:openai:gpt-5.2"; name = "shopify:openai:gpt-5.2"; }
            { id = "shopify:openai:gpt-5.2-2025-12-11"; name = "shopify:openai:gpt-5.2-2025-12-11"; }
            { id = "shopify:openai:gpt-4o-2024-08-06"; name = "shopify:openai:gpt-4o-2024-08-06"; }
            { id = "shopify:openai:gpt-4o-2024-11-20"; name = "shopify:openai:gpt-4o-2024-11-20"; }
            { id = "shopify:openai:gpt-4o"; name = "shopify:openai:gpt-4o"; }
            { id = "shopify:openai:gpt-4o-mini"; name = "shopify:openai:gpt-4o-mini"; }
            { id = "shopify:openai:gpt-4o-mini-2024-07-18"; name = "shopify:openai:gpt-4o-mini-2024-07-18"; }
            { id = "shopify:openai:gpt-4o-audio-preview"; name = "shopify:openai:gpt-4o-audio-preview"; }
            { id = "shopify:openai:gpt-4.1-2025-04-14"; name = "shopify:openai:gpt-4.1-2025-04-14"; }
            { id = "shopify:openai:gpt-4.1"; name = "shopify:openai:gpt-4.1"; }
            { id = "shopify:openai:gpt-4.1-mini-2025-04-14"; name = "shopify:openai:gpt-4.1-mini-2025-04-14"; }
            { id = "shopify:openai:gpt-4.1-mini"; name = "shopify:openai:gpt-4.1-mini"; }
            { id = "shopify:openai:gpt-4.1-nano-2025-04-14"; name = "shopify:openai:gpt-4.1-nano-2025-04-14"; }
            { id = "shopify:openai:gpt-4.1-nano"; name = "shopify:openai:gpt-4.1-nano"; }
            { id = "shopify:openai:o3-mini"; name = "shopify:openai:o3-mini"; }
            { id = "shopify:openai:o3-2025-04-16"; name = "shopify:openai:o3-2025-04-16"; }
            { id = "shopify:openai:o4-mini-2025-04-16"; name = "shopify:openai:o4-mini-2025-04-16"; }
            { id = "shopify:openai:text-embedding-3-small"; name = "shopify:openai:text-embedding-3-small"; }
            { id = "shopify:openai:text-embedding-3-large"; name = "shopify:openai:text-embedding-3-large"; }
            { id = "shopify:openai:text-embedding-ada-002"; name = "shopify:openai:text-embedding-ada-002"; }
            { id = "shopify:openai:gpt-image-1"; name = "shopify:openai:gpt-image-1"; }
            { id = "shopify:openai:tts-1"; name = "shopify:openai:tts-1"; }
            { id = "shopify:openai:gpt-3.5-turbo-0125"; name = "shopify:openai:gpt-3.5-turbo-0125"; }
            { id = "shopify:openai:gpt-3.5-turbo-0613"; name = "shopify:openai:gpt-3.5-turbo-0613"; }
            { id = "shopify:openai:gpt-3.5-turbo-1106"; name = "shopify:openai:gpt-3.5-turbo-1106"; }
            { id = "shopify:openai:gpt-4-turbo-2024-04-09"; name = "shopify:openai:gpt-4-turbo-2024-04-09"; }
            { id = "shopify:openai:gpt-4-turbo-preview"; name = "shopify:openai:gpt-4-turbo-preview"; }
            { id = "shopify:openai:gpt-4-0125-preview"; name = "shopify:openai:gpt-4-0125-preview"; }
            { id = "shopify:openai:gpt-4-0314"; name = "shopify:openai:gpt-4-0314"; }
            { id = "shopify:openai:gpt-4-0613"; name = "shopify:openai:gpt-4-0613"; }
            { id = "shopify:openai:gpt-4-1106-preview"; name = "shopify:openai:gpt-4-1106-preview"; }
            { id = "shopify:openai:gpt-4o-audio-preview-2024-10-01"; name = "shopify:openai:gpt-4o-audio-preview-2024-10-01"; }
            { id = "shopify:openai:gpt-4o-2024-05-13"; name = "shopify:openai:gpt-4o-2024-05-13"; }
            { id = "shopify:openai:gpt-4o-realtime-preview"; name = "shopify:openai:gpt-4o-realtime-preview"; }
            { id = "shopify:openai:gpt-4o-realtime-preview-2025-06-03"; name = "shopify:openai:gpt-4o-realtime-preview-2025-06-03"; }
            { id = "shopify:openai:gpt-4o-realtime-preview-2024-12-17"; name = "shopify:openai:gpt-4o-realtime-preview-2024-12-17"; }
            { id = "shopify:openai:gpt-4o-realtime-preview-2024-10-01"; name = "shopify:openai:gpt-4o-realtime-preview-2024-10-01"; }
            { id = "shopify:openai:dall-e-3"; name = "shopify:openai:dall-e-3"; }
            { id = "shopify:openai:o1"; name = "shopify:openai:o1"; }
            { id = "shopify:openai:o1-2024-12-17"; name = "shopify:openai:o1-2024-12-17"; }
            { id = "shopify:openai:o1-mini-2024-09-12"; name = "shopify:openai:o1-mini-2024-09-12"; }
            { id = "shopify:openai:o3"; name = "shopify:openai:o3"; }
            { id = "shopify:openai:o3-mini-2025-01-31"; name = "shopify:openai:o3-mini-2025-01-31"; }
            { id = "shopify:openai:o4-mini"; name = "shopify:openai:o4-mini"; }
            { id = "shopify:google:gemini-2.5-flash-lite-preview-06-17"; name = "shopify:google:gemini-2.5-flash-lite-preview-06-17"; }
            { id = "shopify:google:gemini-2.5-flash-lite-preview"; name = "shopify:google:gemini-2.5-flash-lite-preview"; }
            { id = "shopify:google:gemini-2.5-flash-lite-preview-09-2025"; name = "shopify:google:gemini-2.5-flash-lite-preview-09-2025"; }
            { id = "shopify:google:gemini-flash-lite-latest"; name = "shopify:google:gemini-flash-lite-latest"; }
            { id = "shopify:google:gemini-2.5-flash-lite"; name = "shopify:google:gemini-2.5-flash-lite"; }
            { id = "shopify:google:gemini-2.5-flash-preview-09-2025"; name = "shopify:google:gemini-2.5-flash-preview-09-2025"; }
            { id = "shopify:google:gemini-flash-latest"; name = "shopify:google:gemini-flash-latest"; }
            { id = "shopify:google:gemini-2.5-flash"; name = "shopify:google:gemini-2.5-flash"; }
            { id = "shopify:google:gemini-2.5-pro"; name = "shopify:google:gemini-2.5-pro"; }
            { id = "shopify:google:gemini-embedding-001"; name = "shopify:google:gemini-embedding-001"; }
            { id = "shopify:google:gemini-3-flash-preview"; name = "shopify:google:gemini-3-flash-preview"; }
            { id = "shopify:google:gemini-3-pro-image-preview"; name = "shopify:google:gemini-3-pro-image-preview"; }
            { id = "shopify:google:gemini-3.1-pro-preview"; name = "shopify:google:gemini-3.1-pro-preview"; }
            { id = "shopify:google:gemini-3-pro-preview"; name = "shopify:google:gemini-3-pro-preview"; }
            { id = "shopify:google:gemini-1.5-pro"; name = "shopify:google:gemini-1.5-pro"; }
            { id = "shopify:google:gemini-1.5-flash"; name = "shopify:google:gemini-1.5-flash"; }
            { id = "shopify:google:gemini-1.5-flash-8b"; name = "shopify:google:gemini-1.5-flash-8b"; }
            { id = "shopify:google:gemini-1.0-pro-vision"; name = "shopify:google:gemini-1.0-pro-vision"; }
            { id = "shopify:google:gemini-2.0-flash"; name = "shopify:google:gemini-2.0-flash"; }
            { id = "shopify:google:gemini-2.0-flash-001"; name = "shopify:google:gemini-2.0-flash-001"; }
            { id = "shopify:google:gemini-2.0-flash-lite"; name = "shopify:google:gemini-2.0-flash-lite"; }
            { id = "shopify:google:gemini-2.0-flash-lite-preview-02-05"; name = "shopify:google:gemini-2.0-flash-lite-preview-02-05"; }
            { id = "shopify:google:gemini-2.5-pro-exp-03-25"; name = "shopify:google:gemini-2.5-pro-exp-03-25"; }
            { id = "shopify:google:gemini-2.5-pro-preview-05-06"; name = "shopify:google:gemini-2.5-pro-preview-05-06"; }
            { id = "shopify:google:gemini-2.5-pro-preview-03-25"; name = "shopify:google:gemini-2.5-pro-preview-03-25"; }
            { id = "shopify:google:gemini-2.5-pro-preview-06-05"; name = "shopify:google:gemini-2.5-pro-preview-06-05"; }
            { id = "shopify:google:gemini-2.5-flash-preview-04-17"; name = "shopify:google:gemini-2.5-flash-preview-04-17"; }
            { id = "shopify:google:gemini-2.5-flash-preview-05-20"; name = "shopify:google:gemini-2.5-flash-preview-05-20"; }
            { id = "shopify:google:gemini-2.0-flash-thinking-exp"; name = "shopify:google:gemini-2.0-flash-thinking-exp"; }
            { id = "shopify:google:gemini-2.0-flash-thinking-exp-01-21"; name = "shopify:google:gemini-2.0-flash-thinking-exp-01-21"; }
            { id = "shopify:google:gemini-2.0-flash-lite-preview"; name = "shopify:google:gemini-2.0-flash-lite-preview"; }
            { id = "shopify:google:embedding-001"; name = "shopify:google:embedding-001"; }
            { id = "shopify:google:embedding-gecko-001"; name = "shopify:google:embedding-gecko-001"; }
            { id = "shopify:google:gemini-embedding-exp-03-07"; name = "shopify:google:gemini-embedding-exp-03-07"; }
            { id = "shopify:google:consumer-agent-gemini-3-flash-lite-preview"; name = "shopify:google:consumer-agent-gemini-3-flash-lite-preview"; }
            { id = "shopify:anthropic:claude-haiku-4-5"; name = "shopify:anthropic:claude-haiku-4-5"; }
            { id = "shopify:anthropic:claude-haiku-4-5@20251001"; name = "shopify:anthropic:claude-haiku-4-5@20251001"; }
            { id = "shopify:anthropic:claude-haiku-4-5-20251001"; name = "shopify:anthropic:claude-haiku-4-5-20251001"; }
            { id = "shopify:anthropic:claude-opus-4-5"; name = "shopify:anthropic:claude-opus-4-5"; }
            { id = "shopify:anthropic:claude-opus-4-5@20251101"; name = "shopify:anthropic:claude-opus-4-5@20251101"; }
            { id = "shopify:anthropic:claude-opus-4-5-20251101"; name = "shopify:anthropic:claude-opus-4-5-20251101"; }
            { id = "shopify:anthropic:claude-opus-4-1"; name = "shopify:anthropic:claude-opus-4-1"; }
            { id = "shopify:anthropic:claude-opus-4-1@20250805"; name = "shopify:anthropic:claude-opus-4-1@20250805"; }
            { id = "shopify:anthropic:claude-opus-4-1-20250805"; name = "shopify:anthropic:claude-opus-4-1-20250805"; }
            { id = "shopify:anthropic:claude-sonnet-4-6"; name = "shopify:anthropic:claude-sonnet-4-6"; }
            { id = "shopify:anthropic:claude-sonnet-4-5"; name = "shopify:anthropic:claude-sonnet-4-5"; }
            { id = "shopify:anthropic:claude-sonnet-4-5@20250929"; name = "shopify:anthropic:claude-sonnet-4-5@20250929"; }
            { id = "shopify:anthropic:claude-sonnet-4-5-20250929"; name = "shopify:anthropic:claude-sonnet-4-5-20250929"; }
            { id = "shopify:anthropic:claude-3-5-sonnet"; name = "shopify:anthropic:claude-3-5-sonnet"; }
            { id = "shopify:anthropic:claude-3-5-sonnet-20240620"; name = "shopify:anthropic:claude-3-5-sonnet-20240620"; }
            { id = "shopify:anthropic:claude-3-5-sonnet@20240620"; name = "shopify:anthropic:claude-3-5-sonnet@20240620"; }
            { id = "shopify:anthropic:claude-3-5-sonnet-v2"; name = "shopify:anthropic:claude-3-5-sonnet-v2"; }
            { id = "shopify:anthropic:claude-3-5-sonnet-20241022"; name = "shopify:anthropic:claude-3-5-sonnet-20241022"; }
            { id = "shopify:anthropic:claude-3-5-sonnet-v2@20241022"; name = "shopify:anthropic:claude-3-5-sonnet-v2@20241022"; }
            { id = "shopify:anthropic:claude-3-haiku"; name = "shopify:anthropic:claude-3-haiku"; }
            { id = "shopify:anthropic:claude-3-haiku-20240307"; name = "shopify:anthropic:claude-3-haiku-20240307"; }
            { id = "shopify:anthropic:claude-3-haiku@20240307"; name = "shopify:anthropic:claude-3-haiku@20240307"; }
            { id = "shopify:anthropic:claude-3-opus"; name = "shopify:anthropic:claude-3-opus"; }
            { id = "shopify:anthropic:claude-3-opus-v1"; name = "shopify:anthropic:claude-3-opus-v1"; }
            { id = "shopify:anthropic:claude-3-opus-20240229"; name = "shopify:anthropic:claude-3-opus-20240229"; }
            { id = "shopify:anthropic:claude-3-opus-v1@20240229"; name = "shopify:anthropic:claude-3-opus-v1@20240229"; }
            { id = "shopify:anthropic:claude-3-sonnet"; name = "shopify:anthropic:claude-3-sonnet"; }
            { id = "shopify:anthropic:claude-3-sonnet-20240229"; name = "shopify:anthropic:claude-3-sonnet-20240229"; }
            { id = "shopify:anthropic:claude-3-sonnet@20240229"; name = "shopify:anthropic:claude-3-sonnet@20240229"; }
            { id = "shopify:anthropic:claude-3-5-haiku"; name = "shopify:anthropic:claude-3-5-haiku"; }
            { id = "shopify:anthropic:claude-3-5-haiku-20241022"; name = "shopify:anthropic:claude-3-5-haiku-20241022"; }
            { id = "shopify:anthropic:claude-3-5-haiku@20241022"; name = "shopify:anthropic:claude-3-5-haiku@20241022"; }
            { id = "shopify:anthropic:claude-3-5-haiku-latest"; name = "shopify:anthropic:claude-3-5-haiku-latest"; }
            { id = "shopify:anthropic:claude-3-7-sonnet"; name = "shopify:anthropic:claude-3-7-sonnet"; }
            { id = "shopify:anthropic:claude-3-7-sonnet-20250219"; name = "shopify:anthropic:claude-3-7-sonnet-20250219"; }
            { id = "shopify:anthropic:claude-3-7-sonnet@20250219"; name = "shopify:anthropic:claude-3-7-sonnet@20250219"; }
            { id = "shopify:anthropic:claude-opus-4"; name = "shopify:anthropic:claude-opus-4"; }
            { id = "shopify:anthropic:claude-opus-4-20250514"; name = "shopify:anthropic:claude-opus-4-20250514"; }
            { id = "shopify:anthropic:claude-opus-4@20250514"; name = "shopify:anthropic:claude-opus-4@20250514"; }
            { id = "shopify:anthropic:claude-sonnet-4"; name = "shopify:anthropic:claude-sonnet-4"; }
            { id = "shopify:anthropic:claude-sonnet-4-20250514"; name = "shopify:anthropic:claude-sonnet-4-20250514"; }
            { id = "shopify:anthropic:claude-sonnet-4@20250514"; name = "shopify:anthropic:claude-sonnet-4@20250514"; }
            { id = "openrouter:openai/gpt-5.1-codex-max"; name = "openrouter:openai/gpt-5.1-codex-max"; }
            { id = "openrouter:anthropic/claude-opus-4.5"; name = "openrouter:anthropic/claude-opus-4.5"; }
            { id = "openrouter:anthropic/claude-sonnet-4.5"; name = "openrouter:anthropic/claude-sonnet-4.5"; }
            { id = "openrouter:qwen/qwen3-235b-a22b-2507"; name = "openrouter:qwen/qwen3-235b-a22b-2507"; }

          ];
        };
      };

      agents.defaults.model.primary = "shopify/shopify:openai:gpt-5-nano";

      channels.telegram = {
        tokenFile = config.secrets.items.openclaw-telegram-token.target;
        allowFrom = [ 5248021986 ];
        groups."*".requireMention = true;
      };
    };

    bundledPlugins.goplaces.enable = false;
  };

  systemd.user.services.openclaw-gateway.Service.EnvironmentFile = [
    "${config.home.homeDirectory}/.local/state/openclaw/gateway-token.env"
    "${config.home.homeDirectory}/.local/state/openclaw/llm-proxy.env"
  ];

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
}
