{
  pkgs,
  config,
  ...
}:
let
  uid = config.users.users.surma.uid;
in
{
  services.surmhosting.exposedApps.radarr.target = {
    cfg = {
      system.stateVersion = "25.05";
      users.users.containeruser = {
        inherit uid;
        isNormalUser = true;
      };

      services.radarr.enable = true;
      services.radarr.package = pkgs.radarr;
      services.radarr.user = "containeruser";
      services.radarr.dataDir = "/dump/state/radarr";
      services.radarr.settings.server.port = 8080;
    };

    extraContainerCfg.bindMounts = {
      state = {
        mountPoint = "/dump/state/radarr";
        hostPath = "/dump/state/radarr";
        isReadOnly = false;
      };
      movies = {
        mountPoint = "/dump/Movies";
        hostPath = "/dump/Movies";
        isReadOnly = false;
      };
      torrent = {
        mountPoint = "/dump/state/qbittorrent";
        hostPath = "/dump/state/qbittorrent";
        isReadOnly = false;
      };
    };
  };
}
