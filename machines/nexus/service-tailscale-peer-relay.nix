# Tailscale peer relay. When two tailnet devices cannot connect directly,
# Tailscale relays their UDP traffic through nexus instead of DERP.
#
# archon needs this. WARP on archon tunnels or drops all traffic to the IPs
# in its include list, and one of these is a Shopify office network. From
# there, archon cannot reach dark-archon directly, and DERP is too slow for
# Moonlight. nexus is on the same LAN as archon and has no WARP.
#
# The tailnet policy must also grant the relay capability:
#   { "src": ["<archon>"], "dst": ["<nexus>"],
#     "app": { "tailscale.com/cap/relay": [] } }
{ ... }:
let
  ports = import ./ports.nix;
in
{
  services.tailscale.extraSetFlags = [
    "--relay-server-port=${toString ports.tailscalePeerRelay}"
  ];
  networking.firewall.allowedUDPPorts = [ ports.tailscalePeerRelay ];
}
