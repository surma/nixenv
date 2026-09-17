# ips.nix — single source of truth for stable host addresses.
#
# `domain` is the local DNS suffix used for FQDNs (DHCP search domain and
# AdGuardHome rewrites). Switching the suffix later (for example to
# home.surma.technology) is a one-value edit.
#
# Host keys are the exact DHCP hostnames AdGuardHome knows. `mac`+`ip`
# describe a static DHCP reservation; `ip` without `mac` is a host with no
# lease (nexus, the DHCP server itself, and pylon, the edge VPS, whose `ip`
# is its stable public address). `tailscale` is the optional Tailscale IPv4.
{
  domain = "home.arpa";

  hosts = {
    nexus         = { ip = "10.0.0.2";             tailscale = "100.83.198.90"; };
    citadel       = { mac = "00:e0:4c:03:4b:03";   ip = "10.0.0.3";   tailscale = "100.70.63.93"; };
    homeassistant = { mac = "d8:3a:dd:e7:41:27";   ip = "10.0.0.5";   tailscale = "100.97.65.42"; };
    archon        = { mac = "d8:b3:2f:bd:df:07";   ip = "10.0.2.1";   tailscale = "100.70.35.41"; };
    shopisurm     = { mac = "1a:18:ac:32:24:6c";   ip = "10.0.2.2";   tailscale = "100.79.232.5"; };
    dragoon       = { mac = "36:8f:cc:d6:6f:ff";   ip = "10.0.1.1";   tailscale = "100.95.6.31"; };
    pixel-8a      = { mac = "c6:25:ac:a2:6d:cf";   ip = "10.0.1.11";  tailscale = "100.112.175.25"; };
    wiz-dbb832    = { mac = "98:77:d5:db:b8:32";   ip = "10.0.255.7"; };
    wiz-7e1cba    = { mac = "cc:40:85:7e:1c:ba";   ip = "10.0.255.10"; };
    pylon         = { ip = "49.12.5.28";           ipv6 = "2a01:4f8:c17:731::1"; tailscale = "100.64.107.114"; };
  };
}
