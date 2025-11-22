{
  config,
  ...
}:
let
  uid = config.users.users.surma.uid;
in
{
  services.surmhosting.exposedApps.music.target = {
    cfg = {
      system.stateVersion = "25.05";
      users.users.containeruser = {
        inherit uid;
        isNormalUser = true;
      };

      services.navidrome.enable = true;
      services.navidrome.user = "containeruser";
      services.navidrome.settings = {
        MusicFolder = "/dump/music";
        DataFolder = "/dump/state/navidrome";
        DefaultDownloadableShare = true;
        Address = "0.0.0.0";
        Port = 8080;
      };
    };

    extraContainerCfg.bindMounts = {
      music = {
        mountPoint = "/dump/music";
        hostPath = "/dump/music";
        isReadOnly = true;
      };
      state = {
        mountPoint = "/dump/state/navidrome";
        hostPath = "/dump/state/navidrome";
        isReadOnly = false;
      };
    };
  };
}
