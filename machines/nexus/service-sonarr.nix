{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.sonarr.containerService = {
    wants = [ "secrets.service" ];
    after = [
      "secrets.service"
      "postgresql.service"
    ];
  };

  services.surmhosting.services.sonarr.expose.port = 8080;
  services.surmhosting.services.sonarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.sonarr.enable = true;
      services.sonarr.package = pkgs-unstable.sonarr;
      services.sonarr.user = "containeruser";
      services.sonarr.dataDir = "/dump/state/sonarr";
      services.sonarr.settings = {
        server.port = 8080;
        auth.method = "External";
        postgres = {
          host = "10.201.17.1"; # surmhosting host-side veth address (alpha-stable)
          port = 5432;
          user = "sonarr";
          maindb = "sonarr-main";
          logdb = "sonarr-log";
        };
      };
      services.sonarr.environmentFiles = [
        "/var/lib/credentials/sonarr/env"
      ];
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
      creds = {
        mountPoint = "/var/lib/credentials/sonarr";
        hostPath = "/var/lib/postgres-arr/sonarr";
        isReadOnly = true;
      };
    };
  };
}
