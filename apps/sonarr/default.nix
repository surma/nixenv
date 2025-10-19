{
  pkgs,
  config,
  ...
}:
let
  name = "sonarr";
  port = 4534;
  uid = config.users.users.surma.uid;
in
{
  config = {
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.${name} = {
          rule = "HostRegexp(`^${name}\.surmrock\.hosts\.`)";
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { url = "http://10.200.5.2:${port |> builtins.toString}"; }
        ];
      };
    };

    containers.${name} = {
      config = {
        system.stateVersion = "25.05";
        users.users.containeruser = {
          inherit uid;
          isNormalUser = true;
        };
        networking.firewall.enable = false;

        services.sonarr.enable = true;
        services.sonarr.user = "containeruser";
        services.sonarr.dataDir = "/dump/state/sonarr";
        services.sonarr.settings.server.port = port;
      };

      privateNetwork = true;
      localAddress = "10.200.5.2";
      hostAddress = "10.200.5.1";
      ephemeral = true;
      autoStart = true;

      bindMounts.state = {
        mountPoint = "/dump/state/sonarr";
        hostPath = "/dump/state/sonarr";
        isReadOnly = false;
      };
      bindMounts.series = {
        mountPoint = "/dump/TV";
        hostPath = "/dump/TV";
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
