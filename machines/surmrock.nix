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
    (
      {
        config,
        lib,
        ...
      }:
      with lib;
      let
        cfg = config.services.traefik.quickExpose;
      in
      {
        options = {
          services.traefik.quickExpose = mkOption {
            type = types.attrsOf types.int;
            default = { };
          };
        };
        config = {
          services.traefik.dynamicConfigOptions.http =
            cfg
            |> lib.attrsToList
            |> map (
              { name, value }:
              {
                routers.${name} = {
                  rule = "HostRegexp(`^${name}.surmcluster`)";
                  service = name;
                };

                services.${name}.loadBalancer.servers = [
                  { url = "http://localhost:${builtins.toString value}"; }
                ];
              }
            )
            |> lib.fold (a: b: lib.recursiveUpdate a b) { };
        };
      }
    )
  ];

  nix.settings.require-sigs = false;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "surmrock";
  networking.networkmanager.enable = true;

  users.users.surma.linger = true;
  users.groups.podman.members = [ "surma" ];

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmbook
  ];

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

  services.hate.enable = true;
  services.navidrome.enable = true;
  services.navidrome.settings = {
    MusicFolder = "/dump/music";
    DataFolder = "/dump/state/navidrome";
    DefaultDownloadableShare = true;
    Port = 4533;
  };
  services.traefik.quickExpose = {
    music = config.services.navidrome.settings.Port;
  };

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
  services.traefik.quickExpose = {
    lidarr = config.services.lidarr.settings.server.port;
  };

  services.radarr.enable = true;
  services.radarr.user = "arr";
  services.radarr.dataDir = "/dump/state/radarr";
  services.radarr.settings.server.port = 4535;
  services.traefik.quickExpose = {
    radarr = config.services.radarr.settings.server.port;
  };

  services.sonarr.enable = true;
  services.sonarr.user = "arr";
  services.sonarr.dataDir = "/dump/state/sonarr";
  services.sonarr.settings.server.port = 4536;
  services.traefik.quickExpose = {
    sonarr = config.services.sonarr.settings.server.port;
  };

  services.prowlarr.enable = true;
  services.prowlarr.settings.server.port = 4537;
  services.traefik.quickExpose = {
    prowlarr = config.services.prowlarr.settings.server.port;
  };

  services.qbittorrent.enable = true;
  services.qbittorrent.user = "arr";
  services.qbittorrent.webuiPort = 4538;
  services.qbittorrent.profileDir = "/dump/state/qbittorrent";
  services.traefik.quickExpose = {
    torrent = config.services.qbittorrent.webuiPort;
  };

  home-manager.users.surma =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../home-manager/claude-code

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

        programs.claude-code.enable = true;
        defaultConfigs.claude-code.enable = true;
      };
    };

  services.traefik = {
    enable = true;
    group = "podman";
    staticConfigOptions = {
      api = {
        dashboard = true;
      };
      providers.docker = { };
      entryPoints = {
        web.address = ":80";
        #   websecure = {
        #     address = ":443";
        #     asDefault = true;
        #     http.tls.certResolver = "letsencrypt";
        #   };
      };
      #   certificatesResolvers.letsencrypt.acme = {
      #     email = "surma@surma.dev";
      #     storage = "/var/lib/traefik/acme.json";
      #     httpChallenge.entryPoint = "web";
      #   };
    };
    dynamicConfigOptions = {
      http.routers.api = {
        service = "api@internal";
        entryPoints = [ "web" ];
        rule = "HostRegexp(`^dashboard\\.surmcluster`)";
      };
    };
  };

  networking.firewall.enable = false;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.openssh.enable = true;

  system.stateVersion = "25.05";
}
