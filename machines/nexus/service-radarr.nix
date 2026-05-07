{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.radarr.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" "postgresql.service" ];
  };

  services.surmhosting.services.radarr.expose.port = 8080;
  services.surmhosting.services.radarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.radarr.enable = true;
      services.radarr.package = pkgs-unstable.radarr;
      services.radarr.user = "containeruser";
      services.radarr.dataDir = "/dump/state/radarr";
      services.radarr.settings = {
        server.port = 8080;
        auth.method = "External";
        postgres = {
          host = "10.201.13.1"; # surmhosting host-side veth address (alpha-stable)
          port = 5432;
          user = "radarr";
          maindb = "radarr-main";
          logdb = "radarr-log";
        };
      };
      services.radarr.environmentFiles = [
        "/var/lib/credentials/radarr/env"
      ];
    };

    bindMounts = {
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
      creds = {
        mountPoint = "/var/lib/credentials/radarr";
        hostPath = "/var/lib/postgres-arr/radarr";
        isReadOnly = true;
      };
    };
  };
}
