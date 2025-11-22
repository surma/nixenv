{
  config,
  ...
}:
let
  torrentingPort = 60123;
  uid = config.users.users.surma.uid;
in
{
  config = {

    networking.firewall.allowedTCPPorts = [ torrentingPort ];
    networking.firewall.allowedUDPPorts = [ torrentingPort ];

    services.surmhosting.exposedApps.torrent.target = {
      cfg = {
        system.stateVersion = "25.05";
        users.users.containeruser = {
          inherit uid;
          isNormalUser = true;
        };

        services.qbittorrent.enable = true;
        services.qbittorrent.user = "containeruser";
        services.qbittorrent.webuiPort = 8080;
        services.qbittorrent.torrentingPort = torrentingPort;
        services.qbittorrent.profileDir = "/dump/state/qbittorrent";
      };

      extraContainerCfg = {
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
  };
}
