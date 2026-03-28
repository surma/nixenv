{ pkgs, inputs, ... }:
{
  secrets.items.dashboard-server-env.command = ''
    mkdir -p /var/lib/overview
    cat > /var/lib/overview/server.env
    chmod 0644 /var/lib/overview/server.env
  '';

  services.surmhosting.services.overview.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.overview.expose.port = 8080;
  services.surmhosting.services.overview.container = {
    config = {
      system.stateVersion = "25.05";

      systemd.services.overview-server = {
        enable = true;
        description = "Overview dashboard server";
        wantedBy = [ "multi-user.target" ];
        environment = {
          OVERVIEW_HOST = "0.0.0.0";
          OVERVIEW_PORT = "8080";
          GOOGLE_CALENDAR_ID = "surma@surmair.de";
          HA_BASE_URL = "https://ha.surma.technology";
          HA_CLIMATE_ENTITY_ID = "climate.office_btrv_office_btrv";
          HA_TODO_ENTITY_ID = "todo.todo_list";
          SHOPIFY_STOCK_RANGE = "5D";
        };
        serviceConfig = {
          ExecStart = "${inputs.dashboard.packages.${pkgs.stdenv.hostPlatform.system}.server}/bin/overview";
          EnvironmentFile = [ "/var/lib/credentials/overview/server.env" ];
          User = "containeruser";
          Restart = "always";
        };
      };
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/overview";
      hostPath = "/var/lib/overview";
      isReadOnly = true;
    };
  };
}
