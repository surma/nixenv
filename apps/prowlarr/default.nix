{
  pkgs,
  config,
  ...
}:
let
  name = "prowlarr";
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
          { url = "http://10.200.4.2:${port |> builtins.toString}"; }
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

        services.prowlarr.enable = true;
        services.prowlarr.settings.server.port = port;

      };

      privateNetwork = true;
      localAddress = "10.200.4.2";
      hostAddress = "10.200.4.1";
      ephemeral = true;
      autoStart = true;

      bindMounts.state = {
        mountPoint = "/var/lib/private/prowlarr";
        hostPath = "/dump/state/prowlarr";
        isReadOnly = false;
      };
    };
  };
}
