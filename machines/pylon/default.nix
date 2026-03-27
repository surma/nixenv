{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting

    # ../../apps/writing-prompt
  ];

  nix.settings.require-sigs = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "pylon";
  networking.networkmanager.enable = true;

  users.users.surma.linger = true;
  users.groups.podman.members = [ "surma" ];

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmrock
    surmbook
  ];

  networking.interfaces.enp1s0.useDHCP = true;
  networking.interfaces.enp1s0.ipv6.addresses = [
    {
      address = "2a01:4f8:c17:731::1";
      prefixLength = 64;
    }
  ];

  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0"; # Replace eth0 with your actual interface name
  };

  secrets.identity = "/home/surma/.ssh/id_machine";

  home-manager.users.surma = import ./home.nix;

  services.surmhosting.enable = true;
  services.surmhosting.externalInterface = "enp1s0";

  services.surmhosting.hostname = "surmedge";
  services.surmhosting.dashboard.enable = false;
  services.surmhosting.tls.enable = true;
  services.surmhosting.tls.email = "surma@surma.dev";
  services.surmhosting.docker.enable = true;

  # Surm-Auth authentication
  services.surmhosting.auth = {
    domain = "auth.surma.technology";
    github.clientIdFile = "/var/lib/surm-auth/github-client-id";
    github.clientSecretFile = "/var/lib/surm-auth/github-client-secret";
    cookieSecretFile = "/var/lib/surm-auth/cookie-secret";
    cookieDomain = ".surma.technology";
  };

  virtualisation.oci-containers.backend = "podman";

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.traefik.staticConfigOptions.tracing = {
    serviceName = "traefik-edge";
    sampleRate = 1.0;
    otlp = {
      http = {
        endpoint = "http://100.83.198.90:4318/v1/traces";
      };
    };
  };

  # Gitea SSH TCP forwarding
  services.traefik.staticConfigOptions.entryPoints.gitea-ssh = {
    address = ":2222";
  };

  services.traefik.dynamicConfigOptions = {
    tcp = {
      routers.gitea-ssh = {
        rule = "HostSNI(`*`)";
        service = "gitea-ssh";
        entryPoints = [ "gitea-ssh" ];
      };
      services.gitea-ssh.loadBalancer.servers = [
        { address = "100.83.198.90:2222"; }
      ];
    };
    http = {
      routers.music = {
        rule = "Host(`music.surma.technology`)";
        service = "music";
      };
      services.music.loadBalancer = {
        servers = [
          {
            url = "http://music.nexus.hosts.100.83.198.90.nip.io";
          }
        ];
        passHostHeader = false;
      };

      routers.ha = {
        rule = "Host(`ha.surma.technology`)";
        service = "ha";
      };
      services.ha.loadBalancer.servers = [
        {
          url = "http://100.97.65.42:8123";
        }
      ];
    };
  };

  services.tailscale.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
    80
    443
    2222 # Gitea SSH
    22067 # Syncthing relay
  ];
  networking.nftables.enable = true;
  services.openssh.enable = true;

  # LLM Proxy service
  secrets.items.llm-proxy-secret = {
    target = "/var/lib/llm-proxy-credentials/receiver-secret";
    mode = "0644"; # World-readable so llm-proxy user can read it
  };
  secrets.items.llm-proxy-client-key = {
    target = "/var/lib/llm-proxy-credentials/client-key";
    mode = "0644";
  };
  secrets.items.openrouter-api-key = {
    target = "/var/lib/llm-proxy-credentials/openrouter-key";
    mode = "0644";
  };
  secrets.items.syncthing-relay-token = {
    target = "/var/lib/syncthing-relay/token";
    mode = "0400";
  };

  # Surm-Auth secrets
  secrets.items.surm-auth-github-client-id = {
    target = "/var/lib/surm-auth/github-client-id";
    mode = "0644";
  };
  secrets.items.surm-auth-github-client-secret = {
    target = "/var/lib/surm-auth/github-client-secret";
    mode = "0644";
  };
  secrets.items.surm-auth-cookie-secret = {
    target = "/var/lib/surm-auth/cookie-secret";
    mode = "0644";
  };

  # Ensure host directories exist for bind mounts
  systemd.tmpfiles.rules = [
    "d /var/lib/llm-proxy 0755 root root -"
    "d /var/lib/llm-proxy-credentials 0755 root root -"
    "d /var/lib/surm-auth 0755 root root -"
  ];

  systemd.services.syncthing-relay = {
    description = "Private Syncthing relay";
    after = [
      "network-online.target"
      "secrets.service"
    ];
    wants = [
      "network-online.target"
      "secrets.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "syncthing-relay";
      LoadCredential = [ "relay-token:${config.secrets.items.syncthing-relay-token.target}" ];
      ExecStart = let
        relayStart = pkgs.writeShellScript "syncthing-relay-start" ''
          set -euo pipefail

          token_file="$CREDENTIALS_DIRECTORY/relay-token"
          token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"

          exec ${pkgs.syncthing-relay}/bin/strelaysrv \
            --keys=/var/lib/syncthing-relay \
            --listen=:22067 \
            --status-srv= \
            --provided-by=surma \
            --pools= \
            --ext-address=relay.sync.surma.technology:22067 \
            --token="$token"
        '';
      in
      "${relayStart}";
      Restart = "on-failure";
    };
  };

  services.surmhosting.services.llm-proxy = {
    expose.ports = [
      {
        port = 4000;
        hostname = "proxy-llm";
        rule = "Host(`proxy.llm.surma.technology`)";
      }
      {
        port = 8080;
        hostname = "key-llm";
        rule = "Host(`key.llm.surma.technology`)";
      }
      {
        port = 4001;
        hostname = "vendors-llm";
        rule = "Host(`vendors.llm.surma.technology`)";
      }
    ];
    container = {
      config =
        { pkgs, ... }:
        {
          imports = [ ../../modules/services/llm-proxy ];

          system.stateVersion = "25.05";

          services.llm-proxy.enable = true;
          services.llm-proxy.keyReceiver.enable = true;
          services.llm-proxy.keyReceiver.secretFile = "/var/lib/credentials/receiver-secret";
          services.llm-proxy.providers.shopify.enable = true;
          services.llm-proxy.providers.openrouter.enable = true;
          services.llm-proxy.providers.openrouter.keyFile = "/var/lib/credentials/openrouter-key";
          services.llm-proxy.providers.openrouter.models = [
            "qwen/qwen3-235b-a22b-2507"
            "anthropic/claude-opus-4.5"
            "anthropic/claude-sonnet-4.5"
            "openai/gpt-5.1-codex-max"
          ];
          services.llm-proxy.clientAuth.enable = true;
          services.llm-proxy.clientAuth.keyFile = "/var/lib/credentials/client-key";
          services.llm-proxy.disableAllUI = true;

          services.llm-proxy.vendorProxy.enable = true;
        };

      bindMounts = {
        state = {
          mountPoint = "/var/lib/llm-proxy";
          hostPath = "/var/lib/llm-proxy";
          isReadOnly = false;
        };
        credentials = {
          mountPoint = "/var/lib/credentials";
          hostPath = "/var/lib/llm-proxy-credentials";
          isReadOnly = true;
        };
      };
    };
  };

  # Gitea proxy (from nexus) with GitHub auth
  services.surmhosting.services.gitea = {
    host = "gitea.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`gitea.surma.technology`)";
    expose.useTargetHost = true;

    # Enable GitHub authentication
    expose.allowedGitHubUsers = [ "surma" ];
  };

  # Dump proxy (from nexus) with GitHub auth
  services.surmhosting.services.dump = {
    host = "dump.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`dump.surma.technology`)";
    expose.useTargetHost = true;

    # Enable GitHub authentication
    expose.allowedGitHubUsers = [ "surma" ];
  };

  system.stateVersion = "25.05";
}
