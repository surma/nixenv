{
  pkgs,
  config,
  ...
}:
let
  uid = config.users.users.surma.uid;
in
{
  services.surmhosting.exposedApps.lidarr.target = {
    cfg = {
      system.stateVersion = "25.05";
      users.users.containeruser = {
        inherit uid;
        isNormalUser = true;
      };

      services.lidarr.enable = true;
      services.lidarr.package = pkgs.lidarr;
      services.lidarr.user = "containeruser";
      services.lidarr.dataDir = "/dump/state/lidarr";
      services.lidarr.settings.server.port = 8080;
    };

    extraContainerCfg.bindMounts = {
      state = {
        mountPoint = "/dump/state/lidarr";
        hostPath = "/dump/state/lidarr";
        isReadOnly = false;
      };
      music = {
        mountPoint = "/dump/music";
        hostPath = "/dump/music";
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
