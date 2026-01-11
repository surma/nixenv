{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/home-manager/unfree-apps
    ./hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting

    ../../modules/secrets

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

  home-manager.users.surma =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../../modules/home-manager/claude-code

        ../../profiles/home-manager/base.nix
        ../../profiles/home-manager/dev.nix
        ../../profiles/home-manager/nixdev.nix
        ../../profiles/home-manager/linux.nix
        ../../profiles/home-manager/workstation.nix
        # ../../profiles/home-manager/cloud.nix

        ../../modules/home-manager/unfree-apps

      ];

      config = {
        allowedUnfreeApps = [
          "claude-code"
        ];

        home.packages = (
          with pkgs;
          [
          ]
        );

        home.stateVersion = "25.05";

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#pylon";
      };
    };

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

  services.traefik.dynamicConfigOptions = {
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

  services.surmhosting.exposedApps.llm-proxy = {
    target.ports = [
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
    ];
    target.container = {
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
  services.surmhosting.exposedApps.gitea = {
    target.host = "gitea.nexus.hosts.100.83.198.90.nip.io";
    target.port = 8080;
    rule = "Host(`gitea.surma.technology`)";

    # Enable GitHub authentication
    allowedGitHubUsers = [ "surma" ];
  };

  system.stateVersion = "25.05";
}
