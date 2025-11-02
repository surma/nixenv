{
  pkgs,
  config,
  ...
}:
let
  name = "torrent";
  port = 4533;
  torrentingPort = 60123;
  uid = config.users.users.surma.uid;
in
{
  config = {
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.${name} = {
          rule = "HostRegexp(`^${name}\.nexus\.hosts\.`)";
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { url = "http://10.200.2.2:${port |> builtins.toString}"; }
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ torrentingPort ];
    networking.firewall.allowedUDPPorts = [ torrentingPort ];

    containers.${name} = {
      config = {
        system.stateVersion = "25.05";
        users.users.containeruser = {
          inherit uid;
          isNormalUser = true;
        };
        networking.firewall.enable = false;
        networking.useHostResolvConf = true;

        services.qbittorrent.enable = true;
        services.qbittorrent.user = "containeruser";
        services.qbittorrent.webuiPort = port;
        services.qbittorrent.torrentingPort = torrentingPort;
        services.qbittorrent.profileDir = "/dump/state/qbittorrent";
      };

      privateNetwork = true;
      localAddress = "10.200.2.2";
      hostAddress = "10.200.2.1";
      ephemeral = true;
      autoStart = true;

      forwardPorts = [
        {
          containerPort = torrentingPort;
          hostPort = torrentingPort;
          protocol = "tcp";
        }
        {
          containerPort = torrentingPort;
          hostPort = torrentingPort;
          protocol = "udp";
        }
      ];

      bindMounts.state = {
        mountPoint = "/dump/state/qbittorrent";
        hostPath = "/dump/state/qbittorrent";
        isReadOnly = false;
      };
    };
  };
}
