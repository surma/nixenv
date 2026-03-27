{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib;
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
  torrentingPort = 60123;
  dumpPort = 8123;
  giteaPort = 2222;
in
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h4
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting
    ../../modules/services/key-poller

    ../../apps/hate

  ];

  config = mkMerge [
    {
      nix.settings.require-sigs = false;
      secrets.identity = "/home/surma/.ssh/id_machine";
      secrets.items.llm-proxy-secret = {
        target = "/var/lib/key-poller/receiver-secret";
        mode = "0400";
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      boot.kernelPackages = pkgs.linuxPackages_latest;

      networking.hostName = "nexus";
      networking.networkmanager.enable = true;
      networking.nftables.enable = true;
      networking.firewall.enable = true;

      networking.firewall.allowedTCPPorts = [
        8082
        5173
        4096
      ];

      environment.systemPackages = with pkgs; [
        smartmontools
        e2fsprogs
      ];

      users.users.surma.linger = true;
      users.groups.podman.members = [ "surma" ];

      users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
        surma
        dragoon
        archon
      ];

      virtualisation.oci-containers.backend = "podman";

      services.tailscale.enable = true;

      services.surmhosting.enable = true;
      services.surmhosting.hostname = "nexus";
      services.surmhosting.containeruser.uid = config.users.users.surma.uid;
      services.surmhosting.externalInterface = "enp2s0";
      services.surmhosting.dashboard.enable = true;
      services.surmhosting.docker.enable = true;

      services.openssh.enable = true;

      services.key-poller.enable = true;
      services.key-poller.secretFile = "/var/lib/key-poller/receiver-secret";
      services.key-poller.remoteNuBin = "/Users/surma/.nix-profile/bin/nu";
      services.key-poller.remoteGcloudBin = "/Users/surma/.nix-profile/bin/gcloud";

      programs.mosh.enable = true;

      system.stateVersion = "25.05";
    }

    {

      secrets.items.nexus-syncthing.target = "/var/lib/syncthing/key.pem";
      secrets.items.syncthing-relay-token = {
        target = "/var/lib/syncthing/relay-token";
        mode = "0400";
      };
      services.syncthing.enable = true;
      services.syncthing.openDefaultPorts = true;
      services.syncthing.user = "surma";
      services.syncthing.dataDir = "/dump/state/syncthing/data";
      services.syncthing.configDir = "/dump/state/syncthing/config";
      services.syncthing.databaseDir = "/dump/state/syncthing/db";
      services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
      services.syncthing.key = config.secrets.items.nexus-syncthing.target;
      services.syncthing.settings.folders."audiobooks".path = "/dump/audiobooks";
      services.syncthing.settings.folders."audiobooks".devices = [
        "dragoon"
        "arbiter"
      ];
      services.syncthing.settings.folders."scratch".path = "/dump/scratch";
      services.syncthing.settings.folders."scratch".devices = [ "dragoon" ];
      services.syncthing.settings.folders."ebooks".path = "/dump/ebooks";
      services.syncthing.settings.folders."ebooks".devices = [
        "dragoon"
        "arbiter"
      ];
      services.syncthing.settings.folders."surmvault".path = "/dump/surmvault";
      services.syncthing.settings.folders."surmvault".devices = [ "dragoon" ];
      services.syncthing.settings.devices.dragoon.id =
        "TAYU7SA-CCAFI4R-ZLB6FNM-OCPMW5W-6KEYYPI-ANW52FK-DUHVT7Z-L2GYBAB";
      services.syncthing.settings.devices.arbiter.id =
        "7HXMC4G-66H3UDT-BRJ6ATT-3HOXUVN-XIMDBOT-JSFEOO3-HRR3NVF-P4GFUQN";
      services.syncthing.guiAddress = "0.0.0.0:4538";
      services.surmhosting.exposedApps.syncthing.target.port = 4538;

      systemd.services.syncthing-private-relay = {
        description = "Inject private Syncthing relay URL";
        after = [
          "syncthing.service"
          "syncthing-init.service"
          "secrets.service"
        ];
        wants = [
          "syncthing.service"
          "syncthing-init.service"
          "secrets.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = let
            injectRelay = pkgs.writeShellScript "syncthing-private-relay" ''
              set -euo pipefail

              token_file="${config.secrets.items.syncthing-relay-token.target}"
              config_xml="${config.services.syncthing.configDir}/config.xml"
              relay_prefix="relay://relay.sync.surma.technology:22067/"
              api_url="http://127.0.0.1:4538"

              [ -s "$token_file" ]
              [ -f "$config_xml" ]

              api_key="$(${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' "$config_xml")"
              relay_token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"
              relay_url="$relay_prefix?token=$relay_token"

              api_curl() {
                ${pkgs.curl}/bin/curl -fsSk \
                  --retry 60 \
                  --retry-delay 1 \
                  --retry-all-errors \
                  -H "X-API-Key: $api_key" \
                  "$@"
              }

              current_options="$(api_curl "$api_url/rest/config/options")"
              updated_options="$(
                printf '%s' "$current_options" | ${pkgs.jq}/bin/jq --arg relay "$relay_url" --arg prefix "$relay_prefix" '
                  .listenAddresses = (
                    [ $relay ]
                    + ((.listenAddresses // []) | map(select(startswith($prefix) | not)))
                    | unique
                  )
                '
              )"

              printf '%s' "$updated_options" \
                | api_curl -X PUT -d @- "$api_url/rest/config/options" >/dev/null

              restart_required="$(api_curl "$api_url/rest/config/restart-required" | ${pkgs.jq}/bin/jq -r '.requiresRestart')"
              if [ "$restart_required" = "true" ]; then
                api_curl -X POST "$api_url/rest/system/restart" >/dev/null
              fi
            '';
          in
          "${injectRelay}";
        };
      };

    }
    {
      networking.firewall.allowedTCPPorts = [
        1883
      ];
      services.mosquitto.enable = true;
      services.mosquitto.listeners = [
        {
          users.ha.hashedPassword = "$7$101$7KOip01uJDP71vA0$y9vhvHE/pxka3/eQiP+Fs4EVjaXCJ4gwChMtFxiCH/jTDricu5MW3BjMx3XTyo2vXAVgUd/QHKuwoejw8h1OuQ==";
          users.ha.acl = [
            "readwrite #"
          ];
        }
      ];
      services.mosquitto.dataDir = "/dump/state/mosquitto";
      services.mosquitto.persistence = false;
    }
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

      services.surmhosting.exposedApps.openclaw.target.port = 18789;
      systemd.tmpfiles.rules = [
        "d /dump/state/openclaw/home 0755 surma users - -"
      ];
      systemd.services."container@lc-openclaw" = {
        wants = [ "secrets.service" ];
        after = [ "secrets.service" ];
        serviceConfig.MemoryMax = "8G";
      };
      services.surmhosting.exposedApps.openclaw.target.container = {
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
            port = 18789;
            user = "containeruser";
            group = "users";
            createUser = false;
            stateDir = "/var/lib/openclaw/state";
            configPath = "/etc/openclaw/openclaw.hm.json";
            environment = {
              # Keep the declarative Nix config in /etc/openclaw/openclaw.hm.json,
              # but run OpenClaw against a writable+persistent merged config.
              OPENCLAW_CONFIG_PATH = "/var/lib/openclaw/state/openclaw.json";
              CLAWDBOT_CONFIG_PATH = "/var/lib/openclaw/state/openclaw.json";
              # Work around bundled plugin discovery resolving to lib/openclaw/dist/extensions
              # in the gateway package, while manifests live under lib/openclaw/extensions.
              # Note: services.openclaw-gateway.package uses the `openclaw` wrapper buildEnv,
              # but that output does not itself contain lib/openclaw/extensions. Point this at
              # the real gateway package output instead, or bundled channels like Telegram never load.
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
                  # Deep-merge mutable + managed, with managed keys taking precedence.
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
    {

      networking.firewall.allowedTCPPorts = [ giteaPort ];
      services.surmhosting.exposedApps.gitea.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.gitea.enable = true;
          services.gitea.stateDir = "/dump/state/gitea";
          services.gitea.user = "containeruser";
          services.gitea.settings.server.HTTP_PORT = 8080;
          services.gitea.settings.server.SSH_PORT = giteaPort;
          services.gitea.settings.server.START_SSH_SERVER = true;
          # services.openssh.enable = true;
        };

        forwardPorts = [
          {
            containerPort = giteaPort;
            hostPort = giteaPort;
            protocol = "tcp";
          }
        ];

        bindMounts = {
          state = {
            mountPoint = "/dump/state/gitea";
            hostPath = "/dump/state/gitea";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.lidarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.lidarr.enable = true;
          services.lidarr.package = pkgs-unstable.lidarr;
          services.lidarr.user = "containeruser";
          services.lidarr.dataDir = "/dump/state/lidarr";
          services.lidarr.settings.server.port = 8080;
          services.lidarr.settings.auth.method = "External";
        };

        bindMounts = {
          state = {
            mountPoint = "/dump/state/lidarr";
            hostPath = "/dump/state/lidarr";
            isReadOnly = false;
          };
          music = {
            mountPoint = "/dump/music";
            hostPath = "/dump/music";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {

      services.surmhosting.exposedApps.radarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.radarr.enable = true;
          services.radarr.package = pkgs-unstable.radarr;
          services.radarr.user = "containeruser";
          services.radarr.dataDir = "/dump/state/radarr";
          services.radarr.settings.server.port = 8080;
          services.radarr.settings.auth.method = "External";
        };

        bindMounts = {
          state = {
            mountPoint = "/dump/state/radarr";
            hostPath = "/dump/state/radarr";
            isReadOnly = false;
          };
          movies = {
            mountPoint = "/dump/Movies";
            hostPath = "/dump/Movies";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.sonarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.sonarr.enable = true;
          services.sonarr.package = pkgs-unstable.sonarr;
          services.sonarr.user = "containeruser";
          services.sonarr.dataDir = "/dump/state/sonarr";
          services.sonarr.settings.server.port = 8080;
          services.sonarr.settings.auth.method = "External";
        };
        bindMounts = {
          state = {
            mountPoint = "/dump/state/sonarr";
            hostPath = "/dump/state/sonarr";
            isReadOnly = false;
          };
          series = {
            mountPoint = "/dump/TV";
            hostPath = "/dump/TV";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.prowlarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.prowlarr.enable = true;
          services.prowlarr.package = pkgs-unstable.prowlarr;
          services.prowlarr.settings.server.port = 8080;
          services.prowlarr.settings.auth.method = "External";
        };

        bindMounts.state = {
          mountPoint = "/var/lib/private/prowlarr";
          hostPath = "/dump/state/prowlarr";
          isReadOnly = false;
        };
      };
    }
    {
      services.surmhosting.exposedApps.rss.target.port = 80;
      services.surmhosting.exposedApps.rss.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.freshrss.enable = true;
          services.freshrss.dataDir = "/dump/state/freshrss";
          # services.freshrss.user = "containeruser";
          services.freshrss.authType = "none";
          services.freshrss.baseUrl = "http://rss.nexus.hosts.10.0.0.2.nip.io";
        };

        bindMounts.state = {
          mountPoint = "/dump/state/freshrss";
          hostPath = "/dump/state/freshrss";
          isReadOnly = false;
        };
      };
    }
    {
      networking.firewall.allowedTCPPorts = [ torrentingPort ];
      networking.firewall.allowedUDPPorts = [ torrentingPort ];
      services.surmhosting.exposedApps.torrent.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.qbittorrent.enable = true;
          # services.qbittorrent.package = pkgs-unstable.qbittorrent;
          services.qbittorrent.user = "containeruser";
          services.qbittorrent.webuiPort = 8080;
          services.qbittorrent.torrentingPort = torrentingPort;
          services.qbittorrent.profileDir = "/dump/state/qbittorrent";
          services.qbittorrent.serverConfig = {
            Preferences.WebUI = {
              AuthSubnetWhitelistEnabled = true;
              AuthSubnetWhitelist = "0.0.0.0/0";
            };
            BitTorrent.Session = {
              GlobalMaxRatio = 1;
              GlobalMaxSeedingMinutes = 1440;
              MaxRatioAction = 1;
            };
          };
        };

        forwardPorts = [
          {
            containerPort = torrentingPort;
            hostPort = torrentingPort;
            protocol = "tcp";
          }
          {
            containerPort = torrentingPort;
            hostPort = torrentingPort;
            protocol = "udp";
          }
        ];
        bindMounts.state = {
          mountPoint = "/dump/state/qbittorrent";
          hostPath = "/dump/state/qbittorrent";
          isReadOnly = false;
        };
      };
    }
    {

      services.surmhosting.exposedApps.music.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.navidrome.enable = true;
          services.navidrome.package = pkgs-unstable.navidrome;
          services.navidrome.user = "containeruser";
          services.navidrome.settings = {
            MusicFolder = "/dump/music";
            DataFolder = "/dump/state/navidrome";
            DefaultDownloadableShare = true;
            Address = "0.0.0.0";
            Port = 8080;
          };

          # navidrome 0.60.0 uses Taglib's WASM JIT for cover art extraction,
          # which requires memory that is both writable and executable.
          # The stable nixpkgs module sets MemoryDenyWriteExecute = true, but
          # the unstable nixpkgs (where the package comes from) correctly sets
          # it to false. Override it here to fix broken cover art.
          systemd.services.navidrome.serviceConfig.MemoryDenyWriteExecute = lib.mkForce false;
        };

        bindMounts = {
          music = {
            mountPoint = "/dump/music";
            hostPath = "/dump/music";
            isReadOnly = true;
          };
          state = {
            mountPoint = "/dump/state/navidrome";
            hostPath = "/dump/state/navidrome";
            isReadOnly = false;
          };
        };
      };
    }
    {
      secrets.items.nexus-copyparty.command = ''
        cat > /var/lib/copyparty/surma.passwd
        chmod 0644 /var/lib/copyparty/surma.passwd
      '';
      services.surmhosting.exposedApps.copyparty.target.container = {
        config = (
          { ... }:
          {
            imports = [
              inputs.copyparty.nixosModules.default
            ];
            config = {
              system.stateVersion = "25.05";
              services.copyparty.enable = true;
              services.copyparty.user = "containeruser";
              services.copyparty.package = inputs.copyparty.packages.${pkgs.stdenv.system}.copyparty;
              services.copyparty = {
                accounts = {
                  surma.passwordFile = "/var/lib/credentials/copyparty/surma.passwd";
                };
                settings.p = [ 8080 ];
                volumes."/all" = {
                  path = "/dump";
                  access.A = [ "surma" ];
                };
                volumes."/tv" = {
                  path = "/dump/TV";
                  access.r = "*";
                };
                volumes."/movies" = {
                  path = "/dump/Tovies";
                  access.r = "*";
                };
                volumes."/music" = {
                  path = "/dump/music";
                  access.r = "*";
                };
              };
            };
          }
        );

        bindMounts.dump = {
          mountPoint = "/dump";
          hostPath = "/dump";
          isReadOnly = false;
        };
        bindMounts.creds = {
          mountPoint = "/var/lib/credentials/copyparty";
          hostPath = "/var/lib/copyparty";
          isReadOnly = true;
        };
      };
    }
    {
      virtualisation.oci-containers.containers.jellyfin = {
        serviceName = "jellyfin-container";
        image = "jellyfin/jellyfin";
        podman.sdnotify = "healthy";
        volumes = [
          "/dump/state/jellyfin/config:/config"
          "/dump/state/jellyfin/cache:/cache"
          "/dump/TV:/media/TV"
          "/dump/Movies:/media/Movies"
          "/dump/audiobooks:/media/audiobooks"
          "/dump/lol:/media/lol"
        ];
        labels = {
          "traefik.enable" = "true";
          "traefik.http.services.jellyfin.loadbalancer.server.port" = "8096";
          "traefik.http.routers.jellyfin.rule" =
            "HostRegexp(`^jellyfin\\.surmcluster`) || HostRegexp(`^jellyfin\\.nexus\\.hosts`)";
        };
      };
    }
    {

      virtualisation.oci-containers.containers.jaeger = {
        serviceName = "jaeger-container";
        image = "cr.jaegertracing.io/jaegertracing/jaeger:2.11.0";
        ports = [
          "4318:4318"
        ];
        labels = {
          "traefik.enable" = "true";
          "traefik.http.services.jaeger.loadbalancer.server.port" = "16686";
          "traefik.http.routers.jaeger.rule" =
            "HostRegexp(`^jaeger\\.surmcluster`) || HostRegexp(`^jaeger\\.nexus\\.hosts`)";
        };
      };
    }
    {
      services.traefik.staticConfigOptions.tracing = {
        serviceName = "traefik-nexus";
        sampleRate = 1.0;
        otlp = {
          http = {
            endpoint = "http://localhost:4318/v1/traces";
          };
        };
      };
    }

    {
      # services.hate.enable = true;
    }

    {
      services.vsftpd.enable = true;
      services.vsftpd.localUsers = true;
      services.vsftpd.writeEnable = true;
    }

    {
      secrets.items.nexus-redis.target = "/var/lib/redis/password";

      networking.firewall.allowedTCPPorts = [ 6379 ];

      services.surmhosting.exposedApps.redis.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.redis.servers.default = {
            enable = true;
            port = 6379;
            bind = "0.0.0.0";
            requirePassFile = "/var/lib/credentials/redis/password";
          };
        };

        forwardPorts = [
          {
            containerPort = 6379;
            hostPort = 6379;
            protocol = "tcp";
          }
        ];

        bindMounts = {
          state = {
            mountPoint = "/var/lib/redis-default";
            hostPath = "/dump/state/redis";
            isReadOnly = false;
          };
          creds = {
            mountPoint = "/var/lib/credentials/redis";
            hostPath = "/var/lib/redis";
            isReadOnly = true;
          };
        };
      };
    }
    {
      networking.firewall.allowedTCPPorts = [ dumpPort ];
      services.surmhosting.exposedApps.dump.target.port = dumpPort;
      services.surmhosting.exposedApps.dump.target.container = {
        config = {
          system.stateVersion = "25.05";

          systemd.services.dumpd = {
            enable = true;
            description = "Dump service";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${
                inputs.dump.packages.${pkgs.stdenv.system}.default
              }/bin/dumpd --listen 0.0.0.0:${dumpPort |> toString} --dir /var/lib/dump --enable-cors";
              User = "containeruser";
              Restart = "always";
            };
          };
        };

        forwardPorts = [
          {
            containerPort = dumpPort;
            hostPort = dumpPort;
            protocol = "tcp";
          }

        ];

        bindMounts.state = {
          mountPoint = "/var/lib/dump";
          hostPath = "/dumpdump";
          isReadOnly = false;
        };
      };
    }
    {
      services.surmhosting.exposedApps.voice-memos.target.container = {
        config = {
          system.stateVersion = "25.05";

          systemd.services.voice-memos-server = {
            enable = true;
            description = "Voice Memos server";
            wantedBy = [ "multi-user.target" ];
            environment = {
              STORAGE_DIR = "/dump/state/voice-memos";
              SHARED_SECRET = "test1234";
            };
            serviceConfig = {
              ExecStart = "${
                inputs.voice-memos.packages.${pkgs.stdenv.system}.backend-server
              }/bin/voicememos-server";
              User = "containeruser";
              Restart = "always";
            };
          };

          systemd.services.voice-memos-worker = {
            enable = true;
            description = "Voice Memos worker";
            wantedBy = [ "multi-user.target" ];
            environment = {
              STORAGE_DIR = "/dump/state/voice-memos";
            };
            serviceConfig = {
              ExecStart = "${
                inputs.voice-memos.packages.${pkgs.stdenv.system}.backend-worker
              }/bin/voicememos-worker";
              User = "containeruser";
              Restart = "always";
            };
          };
        };

        bindMounts.state = {
          mountPoint = "/dump/state/voice-memos";
          hostPath = "/dump/state/voice-memos";
          isReadOnly = false;
        };
      };
    }
    {
      secrets.items.dashboard-server-env.command = ''
        mkdir -p /var/lib/overview
        cat > /var/lib/overview/server.env
        chmod 0644 /var/lib/overview/server.env
      '';

      systemd.services."container@lc-overview" = {
        wants = [ "secrets.service" ];
        after = [ "secrets.service" ];
      };

      services.surmhosting.exposedApps.overview.target.container = {
        config = {
          system.stateVersion = "25.05";

          systemd.services.overview-server = {
            enable = true;
            description = "Overview dashboard server";
            wantedBy = [ "multi-user.target" ];
            environment = {
              OVERVIEW_HOST = "0.0.0.0";
              OVERVIEW_PORT = "8080";
              GOOGLE_CALENDAR_ID = "surma@surmair.de";
              HA_BASE_URL = "https://ha.surma.technology";
              HA_CLIMATE_ENTITY_ID = "climate.office_btrv_office_btrv";
              HA_TODO_ENTITY_ID = "todo.todo_list";
              SHOPIFY_STOCK_RANGE = "5D";
            };
            serviceConfig = {
              ExecStart = "${inputs.dashboard.packages.${pkgs.stdenv.system}.server}/bin/overview";
              EnvironmentFile = [ "/var/lib/credentials/overview/server.env" ];
              User = "containeruser";
              Restart = "always";
            };
          };
        };

        bindMounts = {
          creds = {
            mountPoint = "/var/lib/credentials/overview";
            hostPath = "/var/lib/overview";
            isReadOnly = true;
          };
        };
      };
    }
    {
      secrets.items.github-runner-pat = {
        target = "/var/lib/github-runner/token";
        mode = "0400";
      };

      # The GitHub runner lives in its own private container subnet.
      # Add that subnet to host NAT so the container can reach api.github.com.
      networking.nat.internalIPs = [ "10.203.0.0/24" ];

      systemd.tmpfiles.rules = [
        "d /dump/state/github-runner 0755 root root - -"
      ];

      systemd.services."container@github-runner" = {
        wants = [ "secrets.service" ];
        after = [ "secrets.service" ];
        serviceConfig = {
          MemoryMax = "8G";
          MemorySwapMax = "8G";
        };
      };

      containers.github-runner = {
        autoStart = true;
        privateNetwork = true;
        localAddress = "10.203.0.2";
        hostAddress = "10.203.0.1";
        ephemeral = true;

        bindMounts = {
          state = {
            mountPoint = "/var/lib/github-runner";
            hostPath = "/dump/state/github-runner";
            isReadOnly = false;
          };
          token = {
            mountPoint = "/var/lib/credentials/github-runner";
            hostPath = "/var/lib/github-runner";
            isReadOnly = true;
          };
        };

        config = { pkgs, ... }: {
          system.stateVersion = "25.05";

          networking.useHostResolvConf = false;
          networking.nameservers = [ "8.8.8.8" ];

          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
            "pipe-operators"
          ];

          users.users.containeruser = {
            isNormalUser = true;
            group = "users";
            home = "/home/containeruser";
            extraGroups = [ "nixbld" ];
          };

          systemd.tmpfiles.rules = [
            "d /home/containeruser 0755 containeruser users - -"
            "d /var/lib/github-runner/work 0755 containeruser users - -"
          ];

          services.github-runners.sl = {
            enable = true;
            url = "https://github.com/surma/sl";
            tokenFile = "/var/lib/credentials/github-runner/token";
            name = "nexus-sl-nix-x64";
            replace = true;
            runnerGroup = "Default";
            user = "containeruser";
            group = "users";
            workDir = "/var/lib/github-runner/work";
            extraLabels = [
              "nix"
              "nixos"
              "nexus"
              "container"
              "x64"
              "sl"
            ];
            extraPackages = with pkgs; [
              bash
              coreutils
              curl
              git
              gnutar
              gzip
              jq
              nushell
              zstd
            ];
            serviceOverrides = {
              StateDirectory = [ "github-runner/sl" ];
              RuntimeDirectory = [ "github-runner/sl" ];
              LogsDirectory = [ "github-runner/sl" ];
              ProtectHome = false;
              PrivateUsers = false;
              PrivateMounts = false;
            };
          };
        };
      };
    }
    {
      home-manager.users.surma = import ./home.nix;
    }
  ];
}
