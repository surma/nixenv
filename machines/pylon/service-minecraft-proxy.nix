{ ... }:
let
  ports = import ./ports.nix;
  # citadel's Tailscale IPv4 (see `tailscale status`). Minecraft has no TLS/SNI,
  # so this is a plain TCP passthrough via a HostSNI(`*`) router, mirroring the
  # gitea-ssh forward.
  citadelTailscale = "100.70.63.93";
in
{
  networking.firewall.allowedTCPPorts = [ ports.minecraft ];

  services.traefik.staticConfigOptions.entryPoints.minecraft.address = ":${toString ports.minecraft}";

  services.traefik.dynamicConfigOptions.tcp = {
    routers.minecraft = {
      rule = "HostSNI(`*`)";
      service = "minecraft";
      entryPoints = [ "minecraft" ];
    };
    services.minecraft.loadBalancer.servers = [
      { address = "${citadelTailscale}:${toString ports.minecraft}"; }
    ];
  };
}
