{ lib, ... }:
let
  ports = import ./ports.nix;
  ips = import ../../ips.nix;
  hosts = ips.hosts;
  leases = lib.filterAttrs (_: v: v ? mac) hosts;
  adminPasswordFile = "/var/lib/adguardhome-reconciler/admin-password";
in
{
  secrets.items.adguardhome-admin-password = {
    target = adminPasswordFile;
    mode = "0400";
  };

  # AdGuard binds the static LAN address, so it must wait until
  # NetworkManager has configured that address.
  systemd.services.adguardhome = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  systemd.services.adguardhome-reconcile-leases = {
    after = [ "secrets.service" ];
    requires = [ "secrets.service" ];
    environment = {
      ADGUARD_USERNAME = "surma";
      ADGUARD_PASSWORD_FILE = adminPasswordFile;
    };
  };

  # DNS (53) and DHCP (67) must not use the plain allowedTCPPorts/
  # allowedUDPPorts lists: Nexus is the public edge, so a global allow rule
  # would publish an open resolver and the admin UI to the internet.
  # DNS and DHCP are LAN-only: the tailnet must not resolve through Nexus.
  # Note that 100.64.0.0/10 must never appear next to these ports. It is
  # CGNAT space, so it shows up as a source range on real WAN links, and the
  # rules apply to every interface. DHCP uses the LAN interface because new
  # clients send requests from 0.0.0.0 before they receive an address.
  # The web UI keeps the tailnet like the internal surmhosting entrypoint in
  # default.nix, so the admin interface works while away from home.
  networking.firewall.extraInputRules = ''
    ip saddr 10.0.0.0/8 udp dport 53 accept comment "adguardhome DNS"
    ip saddr 10.0.0.0/8 tcp dport 53 accept comment "adguardhome DNS"
    iifname "enp1s0" udp dport 67 accept comment "adguardhome DHCP"
    ip saddr { 10.0.0.0/8, 100.64.0.0/10 } tcp dport ${toString ports.adguardHomeWeb} accept comment "adguardhome web UI"
  '';

  # allowDHCP grants CAP_NET_RAW unconditionally so the DHCP server can be
  # enabled from the web UI during the cutover from the Deco.
  #
  # Registry-backed keys below are re-applied from ips.nix on every start;
  # yaml-merge replaces pinned list values wholesale, so UI edits to
  # exactly these keys (dhcpv4.options) revert on restart, and junk keys
  # linger until AdGuardHome re-saves its config. The live custom-option
  # list is provably empty (GET /control/dhcp/status: v4.options/v6.options
  # null), so nothing is overwritten.
  services.adguardhome = {
    enable = true;
    allowDHCP = true;
    host = "0.0.0.0";
    port = ports.adguardHomeWeb;
    mutableSettings = true;

    # Static DHCP reservations from the registry: every ips.nix host with a
    # mac becomes a lease keyed by that MAC. The staticDHCP option and the
    # reconcile units live in ../../modules/services/adguardhome-static-dhcp.
    staticDHCP = builtins.listToAttrs (
      lib.mapAttrsToList (name: v: {
        name = v.mac;
        value = {
          ip = v.ip;
          hostname = name;
        };
      }) leases
    );

    settings = {
      users = [
        {
          name = "surma";
          password = "$2y$12$deFi7bZwEwqSjZLv6qW/Xuur41dFOUKc7G28gAZFT2zAJgZFXW8ui";
        }
      ];

      # AdGuard must not claim port 53 on Podman bridge gateways.
      # Podman's Aardvark DNS provides service discovery on those networks.
      dns = {
        bind_hosts = [ hosts.nexus.ip ];
        bootstrap_dns = [
          "9.9.9.9"
          "149.112.112.112"
        ];
        fallback_dns = [
          "9.9.9.9"
          "149.112.112.112"
        ];
      };

      # Native local-domain support: the DHCP server answers
      # <lease-hostname>.<local_domain_name> for every lease (static and
      # dynamic), so no per-host rewrites are needed. Note: this replaces
      # the UI default suffix "lan" with the registry domain.
      dhcp.local_domain_name = ips.domain;

      # DHCP option 15 hands clients the search domain, so bare hostnames
      # resolve. File schema: dhcpv4 (not v4), dnsmasq-style strings.
      dhcp.dhcpv4.options = [
        "15 text ${ips.domain}"
      ];

      # Exactly one rewrite: Nexus has no DHCP lease (static server
      # address), so the native local-domain feature cannot serve it.
      # Rewrites need enabled = true on this version (LegacyRewrite.Enabled
      # defaults to false and disabled entries are skipped).
      filtering.rewrites = [
        {
          domain = "nexus.${ips.domain}";
          answer = hosts.nexus.ip;
          enabled = true;
        }
      ];
    };
  };

  # Remote admin via the public edge: adguard.apps.surma.technology behind
  # surm-auth with an allowlist grant, same as torrent.apps.surma.technology.
  # The backend is explicitly localhost because adguardhome runs on the host
  # itself (see service-ha-proxy.nix for the explicit-host variant). Direct
  # LAN access on the raw port stays available via the firewall rule above.
  services.surmhosting.services.adguard.backend.host = "localhost";
  services.surmhosting.services.adguard.expose.apps.adguard = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    ports = [
      {
        port = ports.adguardHomeWeb;
        hostname = "adguard";
      }
    ];
  };
}
