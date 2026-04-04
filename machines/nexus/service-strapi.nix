{ pkgs, ... }:
let
  strapi = pkgs.callPackage ../../apps/strapi/build.nix { };
in
{
  secrets.items.nexus-strapi-env.command = ''
    mkdir -p /var/lib/strapi
    cat > /var/lib/strapi/env
    chmod 0644 /var/lib/strapi/env
  '';

  services.surmhosting.services.strapi.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.strapi.expose.port = 1337;
  services.surmhosting.services.strapi.container = {
    config = {
      system.stateVersion = "25.05";

      systemd.services.strapi = {
        enable = true;
        description = "Strapi CMS";
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOST = "0.0.0.0";
          PORT = "1337";
          NODE_ENV = "production";
          DATABASE_FILENAME = "/dump/state/strapi/data.db";
        };
        serviceConfig = {
          ExecStart = "${strapi}/bin/strapi start";
          EnvironmentFile = [ "/var/lib/credentials/strapi/env" ];
          User = "containeruser";
          WorkingDirectory = "${strapi}/lib/strapi";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };

    bindMounts.state = {
      mountPoint = "/dump/state/strapi";
      hostPath = "/dump/state/strapi";
      isReadOnly = false;
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/strapi";
      hostPath = "/var/lib/strapi";
      isReadOnly = true;
    };
  };
}
