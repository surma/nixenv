{ ... }:
let
  ports = import ./ports.nix;
in
{
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
  # enabled from the web UI during the cutover from the Deco. Nothing in the
  # `dhcp` section is pinned here for the same reason: keys present in
  # `settings` are re-applied on every start and would revert UI changes.
  services.adguardhome = {
    enable = true;
    allowDHCP = true;
    host = "0.0.0.0";
    port = ports.adguardHomeWeb;
    mutableSettings = true;
    settings = {
      dns.bootstrap_dns = [
        "9.9.9.9"
        "149.112.112.112"
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
