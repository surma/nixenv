{ ... }:
let
  ports = import ./ports.nix;
in
{
  networking.firewall.allowedTCPPorts = [ ports.torrenting ];
  networking.firewall.allowedUDPPorts = [ ports.torrenting ];

  services.surmhosting.services.torrent.expose.port = 8080;
  services.surmhosting.services.torrent.container = {
    config = {
      system.stateVersion = "25.05";

      services.qbittorrent.enable = true;
      # services.qbittorrent.package = pkgs-unstable.qbittorrent;
      services.qbittorrent.user = "containeruser";
      services.qbittorrent.webuiPort = 8080;
      services.qbittorrent.torrentingPort = ports.torrenting;
      services.qbittorrent.profileDir = "/dump/state/qbittorrent";
      services.qbittorrent.serverConfig = {
        Preferences.WebUI = {
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "0.0.0.0/0";
        };
        BitTorrent.Session = {
          GlobalMaxRatio = 1;
          GlobalMaxSeedingMinutes = 1440;
          MaxRatioAction = 1;
        };
      };
    };

    forwardPorts = [
      {
        containerPort = ports.torrenting;
        hostPort = ports.torrenting;
        protocol = "tcp";
      }
      {
        containerPort = ports.torrenting;
        hostPort = ports.torrenting;
        protocol = "udp";
      }
    ];

    bindMounts.state = {
      mountPoint = "/dump/state/qbittorrent";
      hostPath = "/dump/state/qbittorrent";
      isReadOnly = false;
    };
  };
}
