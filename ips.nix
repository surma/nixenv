# ips.nix — single source of truth for stable host addresses.
#
# `domain` is the local DNS suffix used for FQDNs (DHCP search domain and
# AdGuardHome rewrites). Switching the suffix later (for example to
# home.surma.technology) is a one-value edit.
#
# Host keys are the exact DHCP hostnames AdGuardHome knows. `mac`+`ip`
# describe a static DHCP reservation; `ip` without `mac` is a host with no
# lease (nexus, the DHCP server itself, and pylon, the edge VPS, whose `ip`
# is its stable public address). `tailscale` is the optional Tailscale IPv4
# and `tailscale6` the optional Tailscale IPv6.
#
# Every host with a `tailscale` address is published as
# <host>.vpn.surma.technology by the tailscale-cf-dns service on nexus, with
# an AAAA record when `tailscale6` is also set. Refresh both fields from the
# live tailnet with `nix run .#tailscale-ips-update` (also part of
# update-all), then commit and deploy.
#
# The tool matches ips.nix keys against MagicDNS short names, so a host key
# here and its tailnet machine name have to agree.
#
# The third octet groups hosts by what they are, not by where they sit:
#
#   10.0.0.x  headless and workstation servers that live here at home
#   10.0.1.x  mobile devices that I own
#   10.0.2.x  work devices
#   10.0.255.x  dynamic DHCP pool and appliances with no role of their own
{
  domain = "home.arpa";

  hosts = {
    nexus         = { ip = "10.0.0.2";             tailscale = "100.83.198.90"; tailscale6 = "fd7a:115c:a1e0::fb37:c65a"; };
    citadel       = { mac = "00:e0:4c:03:4b:03";   ip = "10.0.0.3";   tailscale = "100.70.63.93"; tailscale6 = "fd7a:115c:a1e0::d532:3f5d"; };
    homeassistant = { mac = "d8:3a:dd:e7:41:27";   ip = "10.0.0.5";   tailscale = "100.97.65.42"; tailscale6 = "fd7a:115c:a1e0::1901:412b"; };
    archon        = { mac = "d8:b3:2f:bd:df:07";   ip = "10.0.2.1";   tailscale = "100.70.35.41"; tailscale6 = "fd7a:115c:a1e0::fc32:232a"; };
    shopisurm     = { mac = "1a:18:ac:32:24:6c";   ip = "10.0.2.2";   tailscale = "100.79.232.5"; tailscale6 = "fd7a:115c:a1e0::5637:e805"; };
    dragoon       = { mac = "36:8f:cc:d6:6f:ff";   ip = "10.0.1.1";   tailscale = "100.95.6.31"; tailscale6 = "fd7a:115c:a1e0::1d1f:61f"; };
    dark-archon   = { mac = "84:08:3a:a1:8b:b4";   ip = "10.0.1.2";   tailscale = "100.107.230.104"; tailscale6 = "fd7a:115c:a1e0::7932:e669"; };
    pixel-8a      = { mac = "c6:25:ac:a2:6d:cf";   ip = "10.0.1.11";  tailscale = "100.112.175.25"; tailscale6 = "fd7a:115c:a1e0::9401:af19"; };
    wiz-dbb832    = { mac = "98:77:d5:db:b8:32";   ip = "10.0.255.7"; };
    wiz-7e1cba    = { mac = "cc:40:85:7e:1c:ba";   ip = "10.0.255.10"; };
    pylon         = { ip = "49.12.5.28";           ipv6 = "2a01:4f8:c17:731::1"; tailscale = "100.64.107.114"; tailscale6 = "fd7a:115c:a1e0::7e01:6b73"; };
  };
}
