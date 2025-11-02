{
  pkgs,
  config,
  ...
}:
let
  name = "lidarr";
  port = 4534;
  uid = config.users.users.surma.uid;
in
{
  config = {
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.${name} = {
          rule = "HostRegexp(`^${name}\\.nexus\\.hosts\\.`)";
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { url = "http://10.200.3.2:${port |> builtins.toString}"; }
        ];
      };
    };

    containers.${name} = {
      config = {
        nixpkgs.pkgs = pkgs;
        system.stateVersion = "25.05";
        users.users.containeruser = {
          inherit uid;
          isNormalUser = true;
        };
        networking.firewall.enable = false;
        networking.useHostResolvConf = true;

        services.lidarr.enable = true;
        services.lidarr.user = "containeruser";
        services.lidarr.dataDir = "/dump/state/lidarr";
        services.lidarr.settings.server.port = port;
      };

      privateNetwork = true;
      localAddress = "10.200.3.2";
      hostAddress = "10.200.3.1";
      ephemeral = true;
      autoStart = true;

      bindMounts.state = {
        mountPoint = "/dump/state/lidarr";
        hostPath = "/dump/state/lidarr";
        isReadOnly = false;
      };
      bindMounts.music = {
        mountPoint = "/dump/music";
        hostPath = "/dump/music";
        isReadOnly = false;
      };
      bindMounts.torrent = {
        mountPoint = "/dump/state/qbittorrent";
        hostPath = "/dump/state/qbittorrent";
        isReadOnly = false;
      };
    };
  };
}
