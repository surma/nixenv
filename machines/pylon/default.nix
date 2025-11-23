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

  system.stateVersion = "25.05";
}
