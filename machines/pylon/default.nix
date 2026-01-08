{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../../home-manager/unfree-apps.nix
    ./hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../../nixos/base.nix
    ../../nixos/surmhosting.nix

    ../../secrets

    ../../apps/writing-prompt
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
        ../../home-manager/claude-code

        ../../home-manager/base.nix
        ../../home-manager/dev.nix
        ../../home-manager/nixdev.nix
        ../../home-manager/linux.nix
        ../../home-manager/workstation.nix
        # ../../home-manager/cloud.nix

        ../../home-manager/unfree-apps.nix

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
  secrets.items.llm-proxy-secret.target = "/var/lib/llm-proxy-credentials/receiver-secret";
  secrets.items.llm-proxy-client-key.target = "/var/lib/llm-proxy-credentials/client-key";

  # Ensure host directories exist for bind mounts
  systemd.tmpfiles.rules = [
    "d /var/lib/llm-proxy 0755 root root -"
    "d /var/lib/llm-proxy-credentials 0755 root root -"
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
          imports = [ ../../nixos/llm-proxy ];

          system.stateVersion = "25.05";

          services.llm-proxy.enable = true;
          services.llm-proxy.keyReceiver.enable = true;
          services.llm-proxy.keyReceiver.secretFile = "/var/lib/credentials/receiver-secret";
          services.llm-proxy.providers.shopify.enable = true;
          services.llm-proxy.clientAuth.enable = true;
          services.llm-proxy.clientAuth.keyFile = "/var/lib/credentials/client-key";
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

  system.stateVersion = "25.05";
}
