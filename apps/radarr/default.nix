{
  pkgs,
  config,
  ...
}:
let
  name = "radarr";
  port = 4534;
  uid = config.users.users.surma.uid;
in
{
  config = {
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.${name} = {
          rule = "HostRegexp(`^${name}\\.surmrock\\.hosts\\.`)";
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { url = "http://10.200.6.2:${port |> builtins.toString}"; }
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

        services.radarr.enable = true;
        services.radarr.user = "containeruser";
        services.radarr.dataDir = "/dump/state/radarr";
        services.radarr.settings.server.port = port;
      };

      privateNetwork = true;
      localAddress = "10.200.6.2";
      hostAddress = "10.200.6.1";
      ephemeral = true;
      autoStart = true;

      bindMounts.state = {
        mountPoint = "/dump/state/radarr";
        hostPath = "/dump/state/radarr";
        isReadOnly = false;
      };
      bindMounts.movies = {
        mountPoint = "/dump/Movies";
        hostPath = "/dump/Movies";
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
