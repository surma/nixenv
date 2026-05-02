{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./service-syncthing.nix
    ./service-mosquitto.nix
    ./service-scout.nix
    ./service-gitea.nix
    ./service-lidarr.nix
    ./service-radarr.nix
    ./service-sonarr.nix
    ./service-prowlarr.nix
    ./service-rss.nix
    ./service-torrent.nix
    ./service-music.nix
    ./service-copyparty.nix
    ./service-jellyfin.nix
    ./service-jaeger.nix
    ./service-traefik-tracing.nix
    ./service-vsftpd.nix
    ./service-redis.nix
    ./service-ups.nix
    ./service-dump.nix
    ./service-voice-memos.nix
    ./service-overview.nix
    ./service-github-runner.nix
    ./service-gitea-runner.nix
    ./service-nexus-admin.nix
    ./service-brain-serve.nix
    # ./service-hate.nix

    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h4
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting
    ../../modules/services/key-poller
    ../../apps/hate
  ];

  nix.settings = {
    require-sigs = false;
    trusted-users = [ "@wheel" ];
  };

  secrets.identity = "/home/surma/.ssh/id_machine";
  secrets.items.llm-proxy-secret = {
    target = "/var/lib/key-poller/receiver-secret";
    mode = "0400";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.graphics.enable = true;

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

  # Disabled 2026-05-02: receiver on pylon returning HTTP 500.
  # services.key-poller.enable = true;
  # services.key-poller.secretFile = "/var/lib/key-poller/receiver-secret";
  # services.key-poller.remoteNuBin = "/Users/surma/.nix-profile/bin/nu";
  # services.key-poller.remoteGcloudBin = "/Users/surma/.nix-profile/bin/gcloud";

  programs.mosh.enable = true;

  home-manager.users.surma = import ./home.nix;

  system.stateVersion = "25.05";
}
