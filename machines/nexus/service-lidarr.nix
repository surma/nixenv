{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.lidarr.expose.port = 8080;
  services.surmhosting.services.lidarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.lidarr.enable = true;
      services.lidarr.package = pkgs-unstable.lidarr;
      services.lidarr.user = "containeruser";
      services.lidarr.dataDir = "/dump/state/lidarr";
      services.lidarr.settings.server.port = 8080;
      services.lidarr.settings.auth.method = "External";
    };

    bindMounts = {
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
