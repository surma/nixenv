{ pkgs, lib, ... }:
let
  apps = [
    "lidarr"
    "sonarr"
    "radarr"
    "prowlarr"
  ];
  nextcloudDatabase = "nextcloud";
  nextcloudPasswordFile = "/var/lib/postgres-nextcloud/password";

  # Each app gets two databases. The role name matches the app.
  dbs = lib.concatMap (app: [
    "${app}-main"
    "${app}-log"
  ]) apps;
in
{
  # Each *arr secret is an environment file consumed by its container and
  # parsed by postgres-arr-setup. Nextcloud needs a raw password file for the
  # NixOS module's systemd credential.
  secrets.items =
    lib.listToAttrs (
      map (app: {
        name = "${app}-postgres-env";
        value = {
          target = "/var/lib/postgres-arr/${app}/env";
          mode = "0444";
        };
      }) apps
    )
    // {
      nextcloud-postgres-password.command = ''
        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g postgres /var/lib/postgres-nextcloud
        umask 0027
        ${pkgs.coreutils}/bin/cat > ${nextcloudPasswordFile}
        ${pkgs.coreutils}/bin/chown root:postgres ${nextcloudPasswordFile}
        ${pkgs.coreutils}/bin/chmod 0440 ${nextcloudPasswordFile}
      '';
    };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    dataDir = "/dump/state/postgres/17";

    # Listen on every interface; access is gated by pg_hba below + the
    # firewall rules at the bottom of this file.
    settings = {
      listen_addresses = lib.mkForce "*";
      password_encryption = "scram-sha-256";
    };

    # Roles. NixOS only creates them; passwords are set by the oneshots below.
    ensureUsers = map (app: { name = app; }) apps ++ [
      {
        name = nextcloudDatabase;
        ensureDBOwnership = true;
      }
    ];

    # The *arr ownership is fixed below because each role owns two databases.
    # Nextcloud uses ensureDBOwnership because its role and database names match.
    ensureDatabases = dbs ++ [ nextcloudDatabase ];

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

  # Crash recovery after an unclean shutdown fsyncs the whole data directory
  # on /dump, which can exceed the module's default 120 s start timeout
  # (systemd then kills PostgreSQL mid-recovery). Raise only the start
  # timeout to 15 min: NixOS renders the module's TimeoutSec=120 before this
  # key (Nix attrsets are sorted) and systemd applies unit-file assignments
  # in order, so the stop timeout keeps the module's 120 s.
  systemd.services.postgresql.serviceConfig.TimeoutStartSec = "15min";

  # NixOS creates databases before roles. PostgreSQL refuses to clone
  # template1 after the system collation version changes, so repair the
  # template before the generated database setup runs.
  systemd.services.postgresql-setup.preStart = ''
    set -eu
    if [[ -f /dump/state/postgres/17/standby.signal ]]; then
      exit 0
    fi

    if [ "$(
      ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -X -A -t -d postgres \
        -c "SELECT datcollversion IS DISTINCT FROM pg_database_collation_actual_version(oid) FROM pg_database WHERE datname = 'template1'"
    )" = "t" ]; then
      echo "Rebuilding template1 indexes for the current collation version"
      ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -X -d template1 \
        -c 'REINDEX DATABASE template1;'
      ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -X -d postgres \
        -c 'ALTER DATABASE template1 REFRESH COLLATION VERSION;'
    fi
  '';

  # The parent /dump/state is owned by surma, so systemd-tmpfiles refuses to
  # create postgres-owned subdirs under it ("unsafe path transition"). The
  # data directory must therefore be created out-of-band; this is a one-time
  # bootstrap step (see the migration runbook).
  #
  # Required state on disk:
  #   /dump/state/postgres     drwxr-xr-x  postgres:postgres
  #   /dump/state/postgres/17  drwx------  postgres:postgres   (currently active)
  #   /dump/state/postgres/16  drwx------  postgres:postgres   (old PG16 cluster, kept until verified)

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
      # Keep role passwords out of PostgreSQL statement logs on SQL errors.
      export PGOPTIONS='-c log_statement=none -c log_min_error_statement=panic'
      PSQL='${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -X'
      ${lib.concatMapStringsSep "\n" (app: ''
        # Extract the raw password from "<APP>__POSTGRES__PASSWORD=<value>".
        PW=$(${pkgs.gnused}/bin/sed -n 's/^[A-Z]*__POSTGRES__PASSWORD=//p' /var/lib/postgres-arr/${app}/env)
        if [ -z "$PW" ]; then
          echo "no password found in /var/lib/postgres-arr/${app}/env" >&2
          exit 1
        fi
        builtin printf '%s\n%s\n' "$PW" "$PW" |
          $PSQL -d postgres -c '\password ${app}'
        $PSQL -c "ALTER DATABASE \"${app}-main\" OWNER TO \"${app}\";"
        $PSQL -c "ALTER DATABASE \"${app}-log\"  OWNER TO \"${app}\";"
      '') apps}
    '';
  };

  # Nextcloud needs the database before its container performs the first setup.
  # The password is hexadecimal, which makes this SQL interpolation safe.
  systemd.services.postgres-nextcloud-setup = {
    description = "Set the password for the Nextcloud PostgreSQL role";
    restartTriggers = [
      (builtins.hashFile "sha256" ../../secrets/nextcloud-postgres-password.age)
    ];
    # Restart in one transaction so the required container is not left stopped.
    stopIfChanged = false;
    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "secrets.service"
    ];
    # The container requires this unit. Soft dependencies here prevent a
    # routine PostgreSQL restart from stopping the container transitively.
    wants = [
      "postgresql.service"
      "postgresql-setup.service"
      "secrets.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      Group = "postgres";
    };
    script = ''
      set -eu
      # Keep the role password out of PostgreSQL statement logs on SQL errors.
      export PGOPTIONS='-c log_statement=none -c log_min_error_statement=panic'
      PASSWORD="$(${pkgs.coreutils}/bin/cat ${nextcloudPasswordFile})"
      if [[ ! "$PASSWORD" =~ ^[0-9a-f]{64}$ ]]; then
        echo "invalid password in ${nextcloudPasswordFile}" >&2
        exit 1
      fi
      builtin printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" |
        ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -X -d postgres \
          -c '\password ${nextcloudDatabase}'
    '';
  };

  # Open 5432 unconditionally. Auth is gated by pg_hba above (scram-sha-256
  # from localhost, container subnet, LAN, and tailnet only). The per-iface
  # `allowedTCPPorts` form is intentionally avoided because the surmhosting
  # "trustedInterfaces = [ \"ve-+\" ]" rule does not actually match container
  # veths in nftables -- the `+` glob doesn't expand inside an iifname set --
  # so a per-iface 5432 rule scoped to enp2s0/tailscale0 would silently lock
  # out the application containers.
  networking.firewall.allowedTCPPorts = [ 5432 ];

}
