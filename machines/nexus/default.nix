{
  config,
  pkgs,
  inputs,
  ...
}:
let
  torrentingPort = 60123;
in
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h4
    inputs.home-manager.nixosModules.home-manager
    ../../nixos/base.nix
    ../../nixos/surmhosting.nix

    ../../secrets

    ../../apps/hate

    ../../home-manager/unfree-apps.nix
  ];
  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nexus";
  networking.networkmanager.enable = true;

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

  services.tailscale.enable = true;

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "nexus";
  services.surmhosting.containeruser.uid = config.users.users.surma.uid;
  services.surmhosting.externalInterface = "enp2s0";
  services.surmhosting.dashboard.enable = true;
  services.surmhosting.docker.enable = true;

  secrets.items.nexus-syncthing.target = "/var/lib/syncthing/key.pem";
  services.syncthing.enable = true;
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
  services.syncthing.settings.devices.dragoon.id =
    "TAYU7SA-CCAFI4R-ZLB6FNM-OCPMW5W-6KEYYPI-ANW52FK-DUHVT7Z-L2GYBAB";
  services.syncthing.settings.devices.arbiter.id =
    "7HXMC4G-66H3UDT-BRJ6ATT-3HOXUVN-XIMDBOT-JSFEOO3-HRR3NVF-P4GFUQN";
  services.syncthing.guiAddress = "0.0.0.0:4538";
  services.surmhosting.exposedApps.syncthing.target.port = 4538;

  services.mosquitto.enable = true;
  services.mosquitto.listeners = [
    {
      users.ha.hashedPassword = "$7$101$7KOip01uJDP71vA0$y9vhvHE/pxka3/eQiP+Fs4EVjaXCJ4gwChMtFxiCH/jTDricu5MW3BjMx3XTyo2vXAVgUd/QHKuwoejw8h1OuQ==";
      acl = [
        "topic readwrite #"
      ];
    }
  ];
  services.mosquitto.dataDir = "/dump/state/mosquitto";
  services.mosquitto.persistence = false;

  services.surmhosting.exposedApps.lidarr.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.lidarr.enable = true;
      services.lidarr.package = pkgs.lidarr;
      services.lidarr.user = "containeruser";
      services.lidarr.dataDir = "/dump/state/lidarr";
      services.lidarr.settings.server.port = 8080;
    };

    extraContainerCfg.bindMounts = {
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

  services.surmhosting.exposedApps.radarr.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.radarr.enable = true;
      services.radarr.package = pkgs.radarr;
      services.radarr.user = "containeruser";
      services.radarr.dataDir = "/dump/state/radarr";
      services.radarr.settings.server.port = 8080;
    };

    extraContainerCfg.bindMounts = {
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

  services.surmhosting.exposedApps.sonarr.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.sonarr.enable = true;
      services.sonarr.package = pkgs.sonarr;
      services.sonarr.user = "containeruser";
      services.sonarr.dataDir = "/dump/state/sonarr";
      services.sonarr.settings.server.port = 8080;
    };
    extraContainerCfg.bindMounts = {
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

  services.surmhosting.exposedApps.prowlarr.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.prowlarr.enable = true;
      services.prowlarr.package = pkgs.prowlarr;
      services.prowlarr.settings.server.port = 8080;

    };

    extraContainerCfg.bindMounts.state = {
      mountPoint = "/var/lib/private/prowlarr";
      hostPath = "/dump/state/prowlarr";
      isReadOnly = false;
    };
  };

  networking.firewall.allowedTCPPorts = [ torrentingPort ];
  networking.firewall.allowedUDPPorts = [ torrentingPort ];
  services.surmhosting.exposedApps.torrent.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.qbittorrent.enable = true;
      services.qbittorrent.user = "containeruser";
      services.qbittorrent.webuiPort = 8080;
      services.qbittorrent.torrentingPort = torrentingPort;
      services.qbittorrent.profileDir = "/dump/state/qbittorrent";
    };

    extraContainerCfg = {
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
  };

  services.surmhosting.exposedApps.music.target = {
    cfg = {
      system.stateVersion = "25.05";

      services.navidrome.enable = true;
      services.navidrome.user = "containeruser";
      services.navidrome.settings = {
        MusicFolder = "/dump/music";
        DataFolder = "/dump/state/navidrome";
        DefaultDownloadableShare = true;
        Address = "0.0.0.0";
        Port = 8080;
      };
    };

    extraContainerCfg.bindMounts = {
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

  virtualisation.oci-containers.backend = "podman";
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

  services.vsftpd.enable = true;
  services.vsftpd.localUsers = true;
  services.vsftpd.writeEnable = true;

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../../home-manager/opencode

        ../../home-manager/base.nix
        ../../home-manager/dev.nix
        ../../home-manager/nixdev.nix
        ../../home-manager/linux.nix
        ../../home-manager/workstation.nix

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

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#nexus";

        programs.opencode.enable = true;
        defaultConfigs.opencode.enable = true;
      };
    };

  networking.firewall.enable = false;

  services.openssh.enable = true;

  system.stateVersion = "25.05";
}
