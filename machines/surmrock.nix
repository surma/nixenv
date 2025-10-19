{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../home-manager/unfree-apps.nix
    ./surmrock-hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../nixos/base.nix

    ../secrets

    ../apps/hate
    ../apps/traefik.nix
    ../apps/music
    ../apps/torrent
  ];
  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "surmrock";
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;

  users.users.surma.linger = true;
  users.groups.podman.members = [ "surma" ];

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmbook
  ];

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "surmrock";
  services.surmhosting.dashboard.enable = true;
  services.surmhosting.docker.enable = true;

  services.mosquitto.enable = true;
  services.mosquitto.listeners = [
    {
      users.ha.hashedPassword = "$7$101$7KOip01uJDP71vA0$y9vhvHE/pxka3/eQiP+Fs4EVjaXCJ4gwChMtFxiCH/jTDricu5MW3BjMx3XTyo2vXAVgUd/QHKuwoejw8h1OuQ==";
    }
  ];
  services.mosquitto.dataDir = "/dump/state/mosquitto";
  services.mosquitto.persistence = false;

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.jellyfin = {
    serviceName = "jellyfin-container";
    image = "jellyfin/jellyfin";
    podman.sdnotify = "healthy";
    volumes = [
      "/dump/surmcluster/jellyfin:/config"
      "/dump/jellyfin/cache:/cache"
      "/dump/TV:/media/TV"
      "/dump/Movies:/media/Movies"
      "/dump/audiobooks:/media/audiobooks"
      "/dump/lol:/media/lol"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.jellyfin.loadbalancer.server.port" = "8096";
      "traefik.http.routers.jellyfin.rule" = "HostRegexp(`^jellyfin\\.surmcluster`)";
    };
  };

  virtualisation.oci-containers.containers.jaeger = {
    serviceName = "jaeger-container";
    image = "cr.jaegertracing.io/jaegertracing/jaeger:2.11.0";
    ports = [
      "4318:4318"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.jaeger.loadbalancer.server.port" = "16686";
      "traefik.http.routers.jaeger.rule" = "HostRegexp(`^jaeger\\.surmcluster`)";
    };
  };
  networking.firewall.allowedTCPPorts = [ 4318 ];

  services.traefik.staticConfigOptions.tracing = {
    serviceName = "traefik-rock";
    sampleRate = 1.0;
    otlp = {
      http = {
        endpoint = "http://localhost:4318/v1/traces";
      };
    };
  };

  services.hate.enable = true;
  users.users.arr = {
    createHome = false;
    group = "arr";
    isSystemUser = true;
  };
  users.groups.arr = { };

  services.lidarr.enable = true;
  services.lidarr.user = "arr";
  services.lidarr.dataDir = "/dump/state/lidarr";
  services.lidarr.settings.server.port = 4534;
  services.surmhosting.portExpose = {
    lidarr = config.services.lidarr.settings.server.port;
  };

  services.radarr.enable = true;
  services.radarr.user = "arr";
  services.radarr.dataDir = "/dump/state/radarr";
  services.radarr.settings.server.port = 4535;
  services.surmhosting.portExpose = {
    radarr = config.services.radarr.settings.server.port;
  };

  services.sonarr.enable = true;
  services.sonarr.user = "arr";
  services.sonarr.dataDir = "/dump/state/sonarr";
  services.sonarr.settings.server.port = 4536;
  services.surmhosting.portExpose = {
    sonarr = config.services.sonarr.settings.server.port;
  };

  services.prowlarr.enable = true;
  services.prowlarr.settings.server.port = 4537;
  services.surmhosting.portExpose = {
    prowlarr = config.services.prowlarr.settings.server.port;
  };

  services.vsftpd.enable = true;
  services.vsftpd.localUsers = true;

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../home-manager/opencode

        ../home-manager/base.nix
        ../home-manager/dev.nix
        ../home-manager/nixdev.nix
        ../home-manager/linux.nix
        ../home-manager/workstation.nix

        ../home-manager/unfree-apps.nix
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

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmrock";

        programs.opencode.enable = true;
        defaultConfigs.opencode.enable = true;
      };
    };

  networking.firewall.enable = false;

  services.openssh.enable = true;

  system.stateVersion = "25.05";
}
