{
  pkgs,
  config,
  ...
}:
let
  uid = config.users.users.surma.uid;
in
{
  services.surmhosting.exposedApps.sonarr.target = {
    cfg = {
      system.stateVersion = "25.05";
      users.users.containeruser = {
        inherit uid;
        isNormalUser = true;
      };

      services.sonarr.enable = true;
      services.sonarr.package = pkgs.sonarr;
      services.sonarr.user = "containeruser";
      services.sonarr.dataDir = "/dump/state/sonarr";
      services.sonarr.settings.server.port = 8080;
    };
    extraContainerCfg.bindMounts = {
      state = {
        mountPoint = "/dump/state/sonarr";
        hostPath = "/dump/state/sonarr";
        isReadOnly = false;
      };
      series = {
        mountPoint = "/dump/TV";
        hostPath = "/dump/TV";
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
