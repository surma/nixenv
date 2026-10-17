# Overview dashboard (https://gitea.surma.technology/surma/dashboard).
# Runs as a nexus.apps app so pushes to main deploy its `server` package.
{ ... }:
{
  # Preserve the existing secret file consumed by the Overview server.
  secrets.items.dashboard-server-env.command = ''
    mkdir -p /var/lib/overview
    cat > /var/lib/overview/server.env
    chmod 0644 /var/lib/overview/server.env
  '';

  nexus.apps.overview = {
    flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/dashboard.git";
    package = "server";
    program = "overview";
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];

    env = {
      OVERVIEW_HOST = "0.0.0.0";
      OVERVIEW_PORT = "8080";
      GOOGLE_CALENDAR_ID = "surma@surmair.de";
      HA_BASE_URL = "https://ha.surma.technology";
      HA_CLIMATE_ENTITY_ID = "climate.office_btrv_office_btrv";
      HA_TODO_ENTITY_ID = "todo.todo_list";
      SHOPIFY_STOCK_RANGE = "5D";
    };

    # The existing host-side env file is mounted read-only into the container.
    # systemd (root) reads EnvironmentFile= before dropping to containeruser,
    # so no credential is needed (credentials are set up after env files are
    # read, so %d/... would not work here).
    secrets.server-env = "/var/lib/overview/server.env";
    containerConfig = {
      system.stateVersion = "25.05";
      systemd.services.app.serviceConfig.EnvironmentFile = [ "/run/app-secrets/server-env" ];
    };

    expose.apps.overview = {
      access.mode = "allowlist";
      access.seedUsers = [ "surma" ];
      internal.access = "trusted-network";
      ports = [
        {
          port = 8080;
          hostname = "overview";
        }
      ];
    };
  };
}
