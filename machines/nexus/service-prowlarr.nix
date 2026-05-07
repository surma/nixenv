{ pkgs, inputs, ... }:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.prowlarr.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" "postgresql.service" ];
  };

  services.surmhosting.services.prowlarr.expose.port = 8080;
  services.surmhosting.services.prowlarr.container = {
    config = {
      system.stateVersion = "25.05";

      services.prowlarr.enable = true;
      services.prowlarr.package = pkgs-unstable.prowlarr;
      services.prowlarr.settings = {
        server.port = 8080;
        auth.method = "External";
        # Connection details; the PASSWORD comes from environmentFiles below
        # so it is not baked into the world-readable Nix store.
        postgres = {
          host = "10.201.12.1"; # surmhosting host-side veth address
          port = 5432;
          user = "prowlarr";
          maindb = "prowlarr-main";
          logdb = "prowlarr-log";
        };
      };
      services.prowlarr.environmentFiles = [
        "/var/lib/credentials/prowlarr/env"
      ];
    };

    bindMounts.state = {
      mountPoint = "/var/lib/private/prowlarr";
      hostPath = "/dump/state/prowlarr";
      isReadOnly = false;
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/prowlarr";
      hostPath = "/var/lib/postgres-arr/prowlarr";
      isReadOnly = true;
    };
  };
}
