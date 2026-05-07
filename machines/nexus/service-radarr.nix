{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.radarr.expose.port = 8080;
  services.surmhosting.services.radarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.radarr.enable = true;
      services.radarr.package = pkgs-unstable.radarr;
      services.radarr.user = "containeruser";
      services.radarr.dataDir = "/dump/state/radarr";
      services.radarr.settings.server.port = 8080;
      services.radarr.settings.auth.method = "External";

      systemd.services.radarr-sqlite-wal = {
        description = "Enable WAL mode for Radarr SQLite databases";
        wantedBy = [ "radarr.service" ];
        before = [ "radarr.service" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.sqlite ];
        script = ''
          for db in /dump/state/radarr/*.db; do
            [ -f "$db" ] && sqlite3 "$db" "PRAGMA journal_mode=WAL;" && echo "WAL enabled: $db"
          done
        '';
      };
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
    };
  };
}
