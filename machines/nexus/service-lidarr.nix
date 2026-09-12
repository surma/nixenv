{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.lidarr.containerService = {
    wants = [ "secrets.service" ];
    after = [
      "secrets.service"
      "postgresql.service"
    ];
  };

  services.surmhosting.services.lidarr.expose.apps.lidarr = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    ports = [
      {
        port = 8080;
        hostname = "lidarr";
      }
    ];
  };
  services.surmhosting.services.lidarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.lidarr.enable = true;
      services.lidarr.package = pkgs-unstable.lidarr;
      services.lidarr.user = "containeruser";
      services.lidarr.dataDir = "/dump/state/lidarr";
      services.lidarr.settings = {
        server.port = 8080;
        auth.method = "External";
        # Postgres connection. Password comes from environmentFiles below
        # (one-line agenix env file) so it isn't world-readable in the Nix store.
        postgres = {
          # Host-side veth address of THIS container's surmhosting index.
          # All 10.201.x.1 addresses terminate on the host, so Postgres is
          # reachable through the container's own veth regardless of index
          # shifts (verified against the old/new evaluated address maps).
          host = "10.201.12.1";
          port = 5432;
          user = "lidarr";
          maindb = "lidarr-main";
          logdb = "lidarr-log";
        };
      };
      services.lidarr.environmentFiles = [
        "/var/lib/credentials/lidarr/env"
      ];
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
      creds = {
        mountPoint = "/var/lib/credentials/lidarr";
        hostPath = "/var/lib/postgres-arr/lidarr";
        isReadOnly = true;
      };
    };
  };
}
