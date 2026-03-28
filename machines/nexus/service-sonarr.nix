{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.sonarr.expose.port = 8080;
  services.surmhosting.services.sonarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.sonarr.enable = true;
      services.sonarr.package = pkgs-unstable.sonarr;
      services.sonarr.user = "containeruser";
      services.sonarr.dataDir = "/dump/state/sonarr";
      services.sonarr.settings.server.port = 8080;
      services.sonarr.settings.auth.method = "External";
    };

    bindMounts = {
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
