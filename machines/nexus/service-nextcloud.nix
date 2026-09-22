{ pkgs, lib, ... }:
let
  ips = import ../../ips.nix;
  domain = "nextcloud.apps.surma.technology";
  internalDomains = [
    "nextcloud.nexus.${ips.domain}"
    "nextcloud.nexus.hosts.${ips.hosts.nexus.ip}.nip.io"
    "nextcloud.nexus.hosts.${ips.hosts.nexus.tailscale}.nip.io"
  ];
  stateDirectory = "/dump/state/nextcloud";
  # The container root is ephemeral, so persistent bind mounts need a stable
  # in-container owner across restarts.
  nextcloudUid = 2001;
  adminPasswordFile = "${stateDirectory}/secrets/admin-pass";
  databasePasswordDirectory = "/var/lib/postgres-nextcloud";
  containerAdminPasswordFile = "/var/lib/nextcloud-secrets/admin-pass";
  containerDatabasePasswordFile = "/var/lib/nextcloud-database/password";
in
{
  systemd.services.nextcloud-state = {
    description = "Create Nextcloud state directories and initial administrator password";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      umask 077

      ${pkgs.coreutils}/bin/install -d -m 0755 ${stateDirectory}
      ${pkgs.coreutils}/bin/install -d -m 0700 -o ${toString nextcloudUid} -g ${toString nextcloudUid} \
        ${stateDirectory}/home \
        ${stateDirectory}/redis
      ${pkgs.coreutils}/bin/install -d -m 0700 ${stateDirectory}/secrets

      if [ ! -s ${adminPasswordFile} ]; then
        temporaryPassword="$(${pkgs.coreutils}/bin/mktemp ${adminPasswordFile}.tmp.XXXXXX)"
        trap '${pkgs.coreutils}/bin/rm -f "$temporaryPassword"' EXIT
        ${pkgs.openssl}/bin/openssl rand -hex 32 > "$temporaryPassword"
        ${pkgs.coreutils}/bin/mv "$temporaryPassword" ${adminPasswordFile}
        trap - EXIT
      fi

      ${pkgs.coreutils}/bin/chown root:root ${adminPasswordFile}
      ${pkgs.coreutils}/bin/chmod 0400 ${adminPasswordFile}
    '';
  };

  # NixOS configures the host side of the veth in the container post-start.
  # Start setup and the web stack only after that gateway exists.
  systemd.services."container@lc-nextcloud" = {
    postStart = lib.mkAfter ''
      ${pkgs.systemd}/bin/systemctl --machine=lc-nextcloud start nextcloud-setup.service
      ${pkgs.systemd}/bin/systemctl --machine=lc-nextcloud start nextcloud-update-db.service
      ${pkgs.systemd}/bin/systemctl --machine=lc-nextcloud start phpfpm-nextcloud.service
      ${pkgs.systemd}/bin/systemctl --machine=lc-nextcloud start nginx.service nextcloud-cron.timer
    '';
    serviceConfig.TimeoutStartSec = lib.mkForce "10min";
  };

  # This key follows zz-immich, which preserves every existing Surmhosting
  # container and Podman address.
  services.surmhosting.services."zz-nextcloud" = {
    backend."nixos-container" = {
      name = "lc-nextcloud";

      service = {
        requires = [
          "nextcloud-state.service"
          "postgres-nextcloud-setup.service"
        ];
        after = [
          "nextcloud-state.service"
          "postgres-nextcloud-setup.service"
        ];
        serviceConfig.MemoryMax = "8G";
      };

      bindMounts = {
        home = {
          mountPoint = "/var/lib/nextcloud";
          hostPath = "${stateDirectory}/home";
          isReadOnly = false;
        };
        database-password = {
          mountPoint = "/var/lib/nextcloud-database";
          hostPath = databasePasswordDirectory;
          isReadOnly = true;
        };
        redis = {
          mountPoint = "/var/lib/redis-nextcloud";
          hostPath = "${stateDirectory}/redis";
          isReadOnly = false;
        };
        secrets = {
          mountPoint = "/var/lib/nextcloud-secrets";
          hostPath = "${stateDirectory}/secrets";
          isReadOnly = true;
        };
      };

      config = {
        system.stateVersion = "25.05";

        systemd.services = {
          nginx.wantedBy = lib.mkForce [ ];
          phpfpm-nextcloud.wantedBy = lib.mkForce [ ];
          nextcloud-setup = {
            wantedBy = lib.mkForce [ ];
            preStart = ''
              # A failed first install leaves a nonempty config that blocks retries.
              # Preserve every completed installation and remove only partial config.
              partialConfig=/var/lib/nextcloud/config/config.php
              if [[ -s "$partialConfig" ]] &&
                ! ${pkgs.gnugrep}/bin/grep -Eq "['\"]installed['\"][[:space:]]*=>[[:space:]]*true" "$partialConfig"
              then
                ${pkgs.coreutils}/bin/rm -- "$partialConfig"
              fi

              for attempt in {1..30}; do
                if ${pkgs.postgresql_17}/bin/pg_isready -h _gateway -p 5432 -t 1; then
                  break
                fi
                if [[ "$attempt" = 30 ]]; then
                  echo "PostgreSQL is not reachable through the container gateway" >&2
                  exit 1
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done

              PGPASSWORD="$(<"$CREDENTIALS_DIRECTORY/dbpass")" \
                ${pkgs.postgresql_17}/bin/psql --no-password \
                  --host=_gateway --port=5432 --username=nextcloud --dbname=nextcloud \
                  --command='SELECT 1' >/dev/null
            '';
          };
        };
        systemd.timers.nextcloud-cron.wantedBy = lib.mkForce [ ];

        users.users.nextcloud.uid = nextcloudUid;
        users.groups.nextcloud.gid = nextcloudUid;

        services.nextcloud = {
          enable = true;
          package = pkgs.nextcloud33;
          hostName = domain;
          https = true;

          database.createLocally = false;
          config = {
            dbtype = "pgsql";
            dbhost = "_gateway:5432";
            dbname = "nextcloud";
            dbuser = "nextcloud";
            dbpassFile = containerDatabasePasswordFile;
            adminuser = "surma";
            adminpassFile = containerAdminPasswordFile;
          };

          extraApps = {
            inherit (pkgs.nextcloud33Packages.apps)
              calendar
              contacts
              notes
              tasks
              ;
          };

          settings = {
            overwriteprotocol = "https";
            "overwrite.cli.url" = "https://${domain}";
            trusted_domains = internalDomains;
            trusted_proxies = [ "10.201.0.0/16" ];
          };
        };
      };
    };

    # Native clients authenticate with Nextcloud and cannot use Surm-auth's
    # browser redirect flow.
    expose.apps.nextcloud = {
      access.mode = "public";
      internal.access = "trusted-network";
      ports = [
        {
          port = 80;
          hostname = "nextcloud";
        }
      ];
    };
  };
}
