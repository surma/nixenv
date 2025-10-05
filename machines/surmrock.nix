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

  services.navidrome.enable = true;
  services.navidrome.settings = {
    MusicFolder = "/dump/music";
    DataFolder = "/dump/state/navidrome";
    DefaultDownloadableShare = true;
    Port = 4533;
  };
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.music = {
        rule = "HostRegexp(`^music.surmcluster`)";
        service = "music";
      };

      services.music.loadBalancer.servers = [
        { url = "http://localhost:${builtins.toString config.services.navidrome.settings.Port}"; }
      ];
    };
  };

  secrets.items.aria2-token.target = "/run/secrets/aria2-token";
  services.aria2.enable = true;
  services.aria2.rpcSecretFile = config.secrets.items.aria2-token.target;
  services.lidarr.enable = true;
  services.lidarr.dataDir = "/dump/state/lidarr";
  services.lidarr.settings.server.port = 4534;
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.lidarr = {
        rule = "HostRegexp(`^lidarr.surmcluster`)";
        service = "lidarr";
      };

      services.lidarr.loadBalancer.servers = [
        { url = "http://localhost:${builtins.toString config.services.lidarr.settings.server.port}"; }
      ];
    };
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
