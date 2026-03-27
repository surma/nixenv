{ ... }:
let
  ports = import ./ports.nix;
in
{
  networking.firewall.allowedTCPPorts = [ ports.giteaSsh ];

  services.traefik.staticConfigOptions.entryPoints.gitea-ssh.address = ":${toString ports.giteaSsh}";

  services.traefik.dynamicConfigOptions.tcp = {
    routers.gitea-ssh = {
      rule = "HostSNI(`*`)";
      service = "gitea-ssh";
      entryPoints = [ "gitea-ssh" ];
    };
    services.gitea-ssh.loadBalancer.servers = [
      { address = "100.83.198.90:${toString ports.giteaSsh}"; }
    ];
  };
}
