# Use the Nexus binary cache (machines/nexus/service-nix-cache.nix). Nexus CI
# builds every x86_64 machine in this repo on each merge to main, so import
# this only on x86_64 machines.
#
# The URL uses the Tailscale address, so it also works away from home. The
# cache has priority 50, so cache.nixos.org (priority 40) stays first for
# everything it has. When Nexus is unreachable, Nix skips the cache after the
# connect timeout.
{ ... }:
let
  ips = import ../../ips.nix;
in
{
  nix.settings = {
    extra-substituters = [
      "http://cache.nexus.hosts.${ips.hosts.nexus.tailscale}.nip.io:8081"
    ];
    extra-trusted-public-keys = [
      "nexus-cache-1:R+YKKJXazkbCIR/1jFN8BJY52g63YOsPAFCiMdln2LM="
    ];
    connect-timeout = 5;
  };
}
