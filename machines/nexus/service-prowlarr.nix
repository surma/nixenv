{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.prowlarr.expose.port = 8080;
  services.surmhosting.services.prowlarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.prowlarr.enable = true;
      services.prowlarr.package = pkgs-unstable.prowlarr;
      services.prowlarr.settings.server.port = 8080;
      services.prowlarr.settings.auth.method = "External";

      systemd.services.prowlarr-sqlite-wal = {
        description = "Enable WAL mode for Prowlarr SQLite databases";
        wantedBy = [ "prowlarr.service" ];
        before = [ "prowlarr.service" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.sqlite ];
        script = ''
          for db in /var/lib/private/prowlarr/*.db; do
            [ -f "$db" ] && sqlite3 "$db" "PRAGMA journal_mode=WAL;" && echo "WAL enabled: $db"
          done
        '';
      };
    };

    bindMounts.state = {
      mountPoint = "/var/lib/private/prowlarr";
      hostPath = "/dump/state/prowlarr";
      isReadOnly = false;
    };
  };
}
