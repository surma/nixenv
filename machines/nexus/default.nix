{
  config,
  pkgs,
  inputs,
  ...
}:
let
  ips = import ../../ips.nix;
  smartdNotifier =
    let
      noti = pkgs.callPackage ../../packages/noti { defaultMobileDevice = "surmpixel"; };
    in
    pkgs.writeShellApplication {
      name = "smartd-hassio-notify";
      text = ''
        ${pkgs.coreutils}/bin/cat > /dev/null
        export HOME=/var/lib/smartd
        device="''${SMARTD_DEVICESTRING:-unknown disk}"
        message="''${SMARTD_MESSAGE:-SMART reported a problem.}"
        exec ${noti}/bin/noti mobile "$device: $message" --name "SMART on nexus"
      '';
    };
in
{
  imports = [
    ./hardware.nix
    ./service-syncthing.nix
    ./service-mosquitto.nix
    ./service-adguardhome.nix
    ./service-scout.nix
    ./service-gitea.nix
    ./service-hedgedoc2.nix
    ./service-opengist.nix
    ./service-lidarr.nix
    ./service-radarr.nix
    ./service-sonarr.nix
    ./service-prowlarr.nix
    ./service-torrent.nix
    ./service-music.nix
    ./service-copyparty.nix
    ./service-jellyfin.nix
    ./service-jaeger.nix
    ./service-traefik-tracing.nix
    ./service-vsftpd.nix
    ./service-postgresql.nix
    ./service-ups.nix
    ./service-dump.nix
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
    ../../profiles/nixos/headless.nix
    inputs.surmhosting.nixosModules.default
    ../../modules/services/key-poller
    ../../modules/services/adguardhome-static-dhcp
    ../../apps/hate
  ];

  nix.settings.trusted-users = [ "@wheel" ];

  # Scout and the SMART notifier share one Home Assistant token. Each
  # consumer receives only the runtime file format that it needs.
  secrets.items.hassio-token.command = ''
    token="$(cat)"
    mkdir -p /var/lib/scout /var/lib/smartd/.hassio-cli
    printf '%s\n' "$token" > /var/lib/scout/hassio-token
    chown surma:users /var/lib/scout/hassio-token
    chmod 0600 /var/lib/scout/hassio-token
    printf '{"url":"http://${ips.hosts.homeassistant.ip}:8123","token":"%s"}\n' "$token" \
      > /var/lib/smartd/.hassio-cli/settings.json
    chown -R root:root /var/lib/smartd
    chmod 0700 /var/lib/smartd /var/lib/smartd/.hassio-cli
    chmod 0600 /var/lib/smartd/.hassio-cli/settings.json
  '';

  # The receiver secret is consumed by two services with different
  # ownership contracts: the root-only poller state (0400) and the
  # LLM receiver's credential bind-mount (0644). One command writes
  # both destinations from a single stdin read; no competing targets
  # are declared (auth-rework section 6.5).
  secrets.items.llm-proxy-secret.command = ''
    secret="$(cat)"
    mkdir -p /var/lib/key-poller /var/lib/llm-proxy-credentials
    chown root:root /var/lib/llm-proxy-credentials
    chmod 0755 /var/lib/llm-proxy-credentials
    printf '%s\n' "$secret" > /var/lib/key-poller/receiver-secret
    chown root:root /var/lib/key-poller/receiver-secret
    chmod 0400 /var/lib/key-poller/receiver-secret
    printf '%s\n' "$secret" > /var/lib/llm-proxy-credentials/receiver-secret
    chown root:root /var/lib/llm-proxy-credentials/receiver-secret
    chmod 0644 /var/lib/llm-proxy-credentials/receiver-secret
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.graphics.enable = true;

  networking.hostName = "nexus";
  networking.networkmanager = {
    enable = true;
    settings.main.no-auto-default = "*";
    ensureProfiles.profiles.enp1s0 = {
      connection = {
        id = "enp1s0";
        type = "ethernet";
        interface-name = "enp1s0";
        autoconnect = true;
      };
      ipv4 = {
        method = "manual";
        addresses = "${ips.hosts.nexus.ip}/16";
        gateway = "10.0.254.254";
        # T2: sole RA-learned resolver (fe80::1) caused tailscaled DNS
        # forward timeouts; AdGuardHome answers on this host.
        dns = "${ips.hosts.nexus.ip};";
      };
      ipv6 = {
        method = "auto";
        # T2: ignore RA-provided DNS (the router's link-local address);
        # RA addresses and routes are unaffected.
        ignore-auto-dns = true;
      };
    };
  };
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

  services.smartd = {
    enable = true;
    autodetect = false;

    # Short tests run daily. Each RAID disk runs one long test per month,
    # and the dates keep the long tests separate.
    devices = [
      {
        device = "/dev/disk/by-id/ata-WDC_WD60EFAX-68JH4N1_WD-WX12D81ACR0X";
        options = "-s (S/../.././01|L/../01/./05)";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD60EFAX-68JH4N1_WD-WX12D81ACSP4";
        options = "-s (S/../.././02|L/../08/./05)";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD60EFAX-68JH4N1_WD-WX12D81R4CCU";
        options = "-s (S/../.././03|L/../15/./05)";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD60EFAX-68JH4N1_WD-WX12D8135LXT";
        options = "-s (S/../.././04|L/../22/./05)";
      }
      { device = "/dev/disk/by-id/nvme-TEAM_TM8FP6512G_TPBF2509080060200784"; }
    ];

    notifications = {
      wall.enable = false;
      mail = {
        enable = true;
        sender = "smartd@nexus";
        recipient = "surma";
        mailer = "${smartdNotifier}/bin/smartd-hassio-notify";
      };
    };
  };

  systemd.services.smartd = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "secrets.service"
    ];
    requires = [ "secrets.service" ];
  };

  users.groups.podman.members = [ "surma" ];

  # In addition to the keys from profiles/nixos/headless.nix: nexus pulls
  # from these two hosts.
  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    dragoon
    archon
  ];

  services.surmhosting.enable = true;
  services.surmhosting.hostname = "nexus";
  services.surmhosting.containeruser.uid = config.users.users.surma.uid;
  services.surmhosting.externalInterface = "enp1s0";
  services.surmhosting.dashboard.enable = true;

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
    stateHostPath = "/var/lib/surm-auth-state";
    unitDependencies = {
      requires = [ "secrets.service" ];
      after = [ "secrets.service" ];
    };
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
  # and the tailnet; managed container networks (10.201.x.x and 10.203.x.x)
  # fall inside 10/8. Not added to allowedTCPPorts (auth-rework section 3.2).
  networking.firewall.extraInputRules = ''
    ip saddr { 10.0.0.0/8, 100.64.0.0/10 } tcp dport 8081 accept comment "surmhosting internal HTTP"
  '';

  services.key-poller.enable = true;
  systemd.services.key-poller = {
    requires = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };
  services.key-poller.secretFile = "/var/lib/key-poller/receiver-secret";
  # Tried in order, first non-empty key wins. shopisurm is a Mac and keeps its
  # tooling in a standalone home-manager profile under /Users; archon is NixOS
  # with gcloud and nushell in the system profile, so the paths differ.
  services.key-poller.hosts =
    let
      shopisurm = address: {
        inherit address;
        nuBin = "/Users/surma/.nix-profile/bin/nu";
        gcloudBin = "/Users/surma/.nix-profile/bin/gcloud";
      };
      archon = address: {
        inherit address;
        nuBin = "/run/current-system/sw/bin/nu";
        gcloudBin = "/run/current-system/sw/bin/gcloud";
      };
    in
    [
      # LAN address first, Tailscale as the fallback, for each host in turn.
      (shopisurm ips.hosts.shopisurm.ip)
      (shopisurm ips.hosts.shopisurm.tailscale)
      (archon ips.hosts.archon.ip)
      (archon ips.hosts.archon.tailscale)
    ];

  programs.mosh.enable = true;

  home-manager.users.surma = import ./home.nix;

  system.stateVersion = "25.05";
}
