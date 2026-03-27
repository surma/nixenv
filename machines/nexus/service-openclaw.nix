{ pkgs, lib, inputs, ... }:
let
  ports = import ./ports.nix;
in
{
  secrets.items.openclaw-telegram-token.command = ''
    mkdir -p /var/lib/openclaw
    token="$(cat)"
    printf '%s\n' "$token" > /var/lib/openclaw/telegram-token
    chgrp users /var/lib/openclaw/telegram-token
    chmod 0644 /var/lib/openclaw/telegram-token
  '';

  secrets.items.openclaw-gateway-token.command = ''
    mkdir -p /var/lib/openclaw
    token="$(cat)"
    if [ "''${token#OPENCLAW_GATEWAY_TOKEN=}" != "$token" ]; then
      token="''${token#OPENCLAW_GATEWAY_TOKEN=}"
    fi
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$token" > /var/lib/openclaw/gateway-token.env
    chmod 0644 /var/lib/openclaw/gateway-token.env
  '';

  secrets.items.llm-proxy-client-key.command = ''
    mkdir -p /var/lib/openclaw
    key="$(cat)"
    printf '%s\n' "$key" > /var/lib/openclaw/llm-proxy-client-key
    chmod 0644 /var/lib/openclaw/llm-proxy-client-key
    {
      printf 'LLM_PROXY_API_KEY=%s\n' "$key"
      printf 'PI_PROXY_API_KEY=%s\n' "$key"
      printf 'PI_PROXY_AUTH_HEADER=Bearer %s\n' "$key"
      printf 'OPENAI_API_KEY=%s\n' "$key"
      printf 'ANTHROPIC_API_KEY=%s\n' "$key"
      printf 'GEMINI_API_KEY=%s\n' "$key"
      printf 'GOOGLE_API_KEY=%s\n' "$key"
      printf 'GROQ_API_KEY=%s\n' "$key"
      printf 'XAI_API_KEY=%s\n' "$key"
    } > /var/lib/openclaw/llm-proxy.env
    chmod 0644 /var/lib/openclaw/llm-proxy.env
  '';

  services.surmhosting.services.openclaw.expose.port = ports.openclaw;
  systemd.tmpfiles.rules = [
    "d /dump/state/openclaw/home 0755 surma users - -"
  ];

  services.surmhosting.services.openclaw.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig.MemoryMax = "8G";
  };

  services.surmhosting.services.openclaw.container = {
    config = {
      imports = [
        inputs.nix-openclaw.nixosModules.openclaw-gateway
        inputs.home-manager.nixosModules.home-manager
      ];
      system.stateVersion = "25.05";

      users.users.containeruser = {
        isNormalUser = true;
        group = "users";
        home = "/home/containeruser";
      };

      systemd.tmpfiles.rules = [
        "d /home/containeruser 0755 containeruser users - -"
      ];

      programs.nix-ld.enable = true;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = false;
        sharedModules = [
          ../../modules/features/secrets.nix
          ../../modules/features/web-search-cli.nix
        ];
        extraSpecialArgs = {
          inherit inputs;
          system = pkgs.stdenv.system;
          systemManager = "home-manager";
        };
        users.containeruser = import ../openclaw;
      };

      services.openclaw-gateway = {
        enable = true;
        package = inputs.nix-openclaw.packages.${pkgs.stdenv.system}.openclaw;
        port = ports.openclaw;
        user = "containeruser";
        group = "users";
        createUser = false;
        stateDir = "/var/lib/openclaw/state";
        configPath = "/etc/openclaw/openclaw.hm.json";
        environment = {
          OPENCLAW_CONFIG_PATH = "/var/lib/openclaw/state/openclaw.json";
          CLAWDBOT_CONFIG_PATH = "/var/lib/openclaw/state/openclaw.json";
          OPENCLAW_BUNDLED_PLUGINS_DIR = "${inputs.nix-openclaw.packages.${pkgs.stdenv.system}.openclaw-gateway}/lib/openclaw/extensions";
        };
        execStartPre = [
          "${pkgs.writeShellScript "openclaw-prepare-config" ''
            set -euo pipefail

            ${pkgs.coreutils}/bin/mkdir -p /var/lib/openclaw/state

            managed=/etc/openclaw/openclaw.hm.json
            mutable=/var/lib/openclaw/state/openclaw.json
            tmp="$mutable.tmp"

            if [ ! -f "$mutable" ]; then
              ${pkgs.coreutils}/bin/cp "$managed" "$mutable"
            else
              ${pkgs.nushell}/bin/nu -c '
                let mutable = (open /var/lib/openclaw/state/openclaw.json)
                let managed = (open /etc/openclaw/openclaw.hm.json)
                $mutable | merge deep $managed | to json --indent 2
              ' > "$tmp"
              ${pkgs.coreutils}/bin/mv "$tmp" "$mutable"
            fi
          ''}"
        ];
        environmentFiles = [
          "/var/lib/credentials/openclaw/gateway-token.env"
          "/var/lib/credentials/openclaw/llm-proxy.env"
        ];
        servicePath = [
          pkgs.git
          pkgs.nix
          pkgs.openssh
          inputs.home-manager.packages.${pkgs.stdenv.system}.default
          (import ../../modules/home-manager/web-search-cli/package.nix {
            inherit pkgs lib inputs;
            authTokenFile = "/var/lib/credentials/openclaw/llm-proxy-client-key";
          })
        ];
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

          models = {
            mode = "merge";
            providers = {
              openai = {
                api = "openai-responses";
                baseUrl = "https://vendors.llm.surma.technology/openai/v1";
                apiKey = {
                  source = "env";
                  provider = "default";
                  id = "LLM_PROXY_API_KEY";
                };
                models = [ ];
              };

              anthropic = {
                baseUrl = "https://vendors.llm.surma.technology/anthropic";
                apiKey = {
                  source = "env";
                  provider = "default";
                  id = "LLM_PROXY_API_KEY";
                };
                models = [ ];
              };

              google = {
                baseUrl = "https://vendors.llm.surma.technology/googlevertexai-global/v1beta1/projects/shopify-ml-production/locations/global/publishers/google";
                apiKey = {
                  source = "env";
                  provider = "default";
                  id = "LLM_PROXY_API_KEY";
                };
                models = [ ];
              };

              groq = {
                api = "openai-completions";
                baseUrl = "https://vendors.llm.surma.technology/groq/openai/v1";
                apiKey = {
                  source = "env";
                  provider = "default";
                  id = "LLM_PROXY_API_KEY";
                };
                models = [ ];
              };

              xai = {
                api = "openai-completions";
                baseUrl = "https://vendors.llm.surma.technology/xai/v1";
                apiKey = {
                  source = "env";
                  provider = "default";
                  id = "LLM_PROXY_API_KEY";
                };
                models = [ ];
              };
            };
          };

          agents.defaults.workspace = "/var/lib/openclaw/workspace";
          agents.defaults.model.primary = "openai/gpt-5.4";

          channels.telegram = {
            enabled = true;
            tokenFile = "/var/lib/credentials/openclaw/telegram-token";
            allowFrom = [ 5248021986 ];
            groups."*".requireMention = true;
          };
        };
      };
    };

    bindMounts = {
      state = {
        mountPoint = "/var/lib/openclaw";
        hostPath = "/dump/state/openclaw";
        isReadOnly = false;
      };
      home = {
        mountPoint = "/home/containeruser";
        hostPath = "/dump/state/openclaw/home";
        isReadOnly = false;
      };
      creds = {
        mountPoint = "/var/lib/credentials/openclaw";
        hostPath = "/var/lib/openclaw";
        isReadOnly = true;
      };
    };
  };
}
