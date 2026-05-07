{ pkgs, lib, ... }:
let
  apps = [
    "lidarr"
    "sonarr"
    "radarr"
    "prowlarr"
  ];

  # Each app gets two databases. The role name matches the app.
  dbs = lib.concatMap (app: [ "${app}-main" "${app}-log" ]) apps;
in
{
  # Decrypt one env file per app onto the host. Each file is exactly:
  #   <APP>__POSTGRES__PASSWORD=<random>
  # consumed both by the *arr container (as systemd EnvironmentFile, via a
  # read-only bind mount of the per-app directory) and by the
  # postgres-arr-setup oneshot below (parsed for the ALTER USER call).
  #
  # 0444 so the bind-mounted copy inside each container is readable by the
  # container's unprivileged containeruser.
  secrets.items = lib.listToAttrs (
    map (app: {
      name = "${app}-postgres-env";
      value = {
        target = "/var/lib/postgres-arr/${app}/env";
        mode = "0444";
      };
    }) apps
  );

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/dump/state/postgres/16";

    # Listen on every interface; access is gated by pg_hba below + the
    # firewall rules at the bottom of this file.
    settings = {
      listen_addresses = lib.mkForce "*";
      password_encryption = "scram-sha-256";
    };

    # Roles. NixOS only creates them; passwords are set by the oneshot below.
    ensureUsers = map (app: { name = app; }) apps;

    # Empty databases. Ownership is fixed up by the oneshot below because
    # ensureDBOwnership only handles the single-DB-per-user case.
    ensureDatabases = dbs;

    authentication = lib.mkOverride 10 ''
      # TYPE  DATABASE  USER  ADDRESS                 METHOD
      local   all       all                           peer
      host    all       all   127.0.0.1/32            scram-sha-256
      host    all       all   ::1/128                 scram-sha-256
      host    all       all   10.201.0.0/16           scram-sha-256   # surmhosting containers
      host    all       all   10.0.0.0/16             scram-sha-256   # LAN
      host    all       all   100.64.0.0/10           scram-sha-256   # tailnet IPv4
      host    all       all   fd7a:115c:a1e0::/48     scram-sha-256   # tailnet IPv6
    '';
  };

  # The parent /dump/state is owned by surma, so systemd-tmpfiles refuses to
  # create postgres-owned subdirs under it ("unsafe path transition"). The
  # data directory must therefore be created out-of-band; this is a one-time
  # bootstrap step (see the migration runbook).
  #
  # Required state on disk:
  #   /dump/state/postgres     drwxr-xr-x  postgres:postgres
  #   /dump/state/postgres/16  drwx------  postgres:postgres

  # After Postgres is up *and* the agenix env files exist on disk, set each
  # role's password and grant it ownership of its two databases. Idempotent;
  # safe to run on every boot.
  systemd.services.postgres-arr-setup = {
    description = "Set passwords and DB ownership for *arr Postgres roles";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "secrets.service"
    ];
    requires = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    wants = [ "secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      Group = "postgres";
    };
    script = ''
      set -eu
      PSQL='${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -X'
      ${lib.concatMapStringsSep "\n" (app: ''
        # Extract the raw password from "<APP>__POSTGRES__PASSWORD=<value>".
        PW=$(${pkgs.gnused}/bin/sed -n 's/^[A-Z]*__POSTGRES__PASSWORD=//p' /var/lib/postgres-arr/${app}/env)
        if [ -z "$PW" ]; then
          echo "no password found in /var/lib/postgres-arr/${app}/env" >&2
          exit 1
        fi
        $PSQL -c "ALTER USER \"${app}\" WITH PASSWORD '$PW';"
        $PSQL -c "ALTER DATABASE \"${app}-main\" OWNER TO \"${app}\";"
        $PSQL -c "ALTER DATABASE \"${app}-log\"  OWNER TO \"${app}\";"
      '') apps}
    '';
  };

  # Open 5432 unconditionally. Auth is gated by pg_hba above (scram-sha-256
  # from localhost, container subnet, LAN, and tailnet only). The per-iface
  # `allowedTCPPorts` form is intentionally avoided because the surmhosting
  # "trustedInterfaces = [ \"ve-+\" ]" rule does not actually match container
  # veths in nftables -- the `+` glob doesn't expand inside an iifname set --
  # so a per-iface 5432 rule scoped to enp2s0/tailscale0 would silently lock
  # out the *arr containers.
  networking.firewall.allowedTCPPorts = [ 5432 ];
}
