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
    ./service-hedgedoc2.nix
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
    ./service-postgresql.nix
    ./service-ups.nix
    ./service-dump.nix
    ./service-voice-memos.nix
    ./service-overview.nix
    ./service-github-runner.nix
    ./service-gitea-runner.nix
    ./service-nexus-admin.nix
    ./service-brain-serve.nix
    ./service-scout-static.nix
    ./service-jazzy-poisonous-plant-parlour.nix
    ./service-firefly.nix
    ./service-firefly-importer.nix
    ./service-firefly-enricher.nix
    ./service-firefly-categoriser.nix
    ./service-surm-auth.nix
    ./service-llm-proxy.nix
    ./service-ha-proxy.nix
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

  # The receiver secret is consumed by two services with different
  # ownership contracts: the root-only poller state (0400) and the
  # LLM receiver's credential bind-mount (0644). One command writes
  # both destinations from a single stdin read; no competing targets
  # are declared (auth-rework section 6.5).
  secrets.items.llm-proxy-secret.command = ''
    secret="$(cat)"
    mkdir -p /var/lib/key-poller /var/lib/llm-proxy-credentials
    printf '%s\n' "$secret" > /var/lib/key-poller/receiver-secret
    chmod 0400 /var/lib/key-poller/receiver-secret
    printf '%s\n' "$secret" > /var/lib/llm-proxy-credentials/receiver-secret
    chmod 0644 /var/lib/llm-proxy-credentials/receiver-secret
  '';

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
    (builtins.readFile ../../assets/ssh-keys/id_deploy.pub)
  ];

  virtualisation.oci-containers.backend = "podman";

  services.tailscale.enable = true;

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "nexus";
  services.surmhosting.containeruser.uid = config.users.users.surma.uid;
  services.surmhosting.externalInterface = "enp1s0";
  services.surmhosting.dashboard.enable = true;
  services.surmhosting.docker.enable = true;

  # Nexus is now the public edge: it terminates HTTPS for the legacy
  # *.surma.technology domains and the new *.apps.surma.technology
  # namespace (auth-rework sections 3.3 and 6.4, as corrected: HTTP-01
  # per-domain certificates; the apps namespace is a DNS routing entry
  # only, never a certificate wildcard). Setting the namespace also
  # marks the host as migrated: every HTTP exposure must be an explicit
  # logical app.
  services.surmhosting.appsNamespace = "apps.surma.technology";
  services.surmhosting.internalPort = 8081;

  services.surmhosting.tls.enable = true;
  # Per-domain HTTP-01 certificates. No static certDomains: the resolver
  # derives one exact certificate per Host-routed domain.
  services.surmhosting.tls.challenge = "http-01";
  services.surmhosting.tls.email = "surma@surma.dev";

  # surm-auth v2 (auth-rework sections 5 and 6).
  services.surmhosting.auth = {
    enable = true;
    domain = "auth.surma.technology";
    aliases = [ "auth.apps.surma.technology" ];
    cookieDomain = ".surma.technology";
    github.clientIdFile = "/var/lib/surm-auth-credentials/github-client-id";
    github.clientSecretFile = "/var/lib/surm-auth-credentials/github-client-secret";
    cookieSecretFile = "/var/lib/surm-auth-credentials/cookie-secret";
    # Surma's stable numeric GitHub ID (verified via
    # https://api.github.com/users/surma). Never a username.
    bootstrapAdmins = [
      {
        provider = "github";
        id = "234957";
      }
    ];
  };

  # The dedicated internal HTTP entrypoint. Reachable only from the LAN
  # and the tailnet; container veths (10.201.x.x) fall inside 10/8. Not
  # added to allowedTCPPorts (auth-rework section 3.2).
  networking.firewall.extraInputRules = ''
    ip saddr { 10.0.0.0/8, 100.64.0.0/10 } tcp dport 8081 accept comment "surmhosting internal HTTP"
  '';

  services.openssh.enable = true;

  services.key-poller.enable = true;
  systemd.services.key-poller = {
    requires = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };
  services.key-poller.secretFile = "/var/lib/key-poller/receiver-secret";
  services.key-poller.remoteNuBin = "/Users/surma/.nix-profile/bin/nu";
  services.key-poller.remoteGcloudBin = "/Users/surma/.nix-profile/bin/gcloud";

  programs.mosh.enable = true;

  home-manager.users.surma = import ./home.nix;

  system.stateVersion = "25.05";
}
