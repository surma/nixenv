{
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs) callPackage writeShellApplication;
  port = 4533;
  uid = config.users.users.surma.uid;
in
{
  config = {
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.music = {
          rule = "HostRegexp(`^music\.nexus\.hosts\.`)";
          service = "music";
        };

        services.music.loadBalancer.servers = [
          { url = "http://10.200.1.2:${port |> builtins.toString}"; }
        ];
      };
    };

    containers.music = {
      config = {
        system.stateVersion = "25.05";
        users.users.containeruser = {
          inherit uid;
          isNormalUser = true;
        };
        networking.firewall.enable = false;
        networking.useHostResolvConf = true;

        services.navidrome.enable = true;
        services.navidrome.user = "containeruser";
        services.navidrome.settings = {
          MusicFolder = "/dump/music";
          DataFolder = "/dump/state/navidrome";
          DefaultDownloadableShare = true;
          Address = "0.0.0.0";
          Port = port;
        };
      };
      privateNetwork = true;
      localAddress = "10.200.1.2";
      hostAddress = "10.200.1.1";
      ephemeral = true;
      autoStart = true;

      bindMounts.music = {
        mountPoint = "/dump/music";
        hostPath = "/dump/music";
        isReadOnly = true;
      };
      bindMounts.state = {
        mountPoint = "/dump/state/navidrome";
        hostPath = "/dump/state/navidrome";
        isReadOnly = false;
      };
    };
  };
}
