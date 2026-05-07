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

      systemd.services.sonarr-sqlite-wal = {
        description = "Enable WAL mode for Sonarr SQLite databases";
        wantedBy = [ "sonarr.service" ];
        before = [ "sonarr.service" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.sqlite ];
        script = ''
          for db in /dump/state/sonarr/*.db; do
            [ -f "$db" ] && sqlite3 "$db" "PRAGMA journal_mode=WAL;" && echo "WAL enabled: $db"
          done
        '';
      };
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
