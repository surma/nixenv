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

  # The /dump trees are owned by uid/gid 1000 on the host. These containers
  # share the host uid space, so a group with that exact gid is what grants
  # write access. The name is arbitrary; only the number matters.
  dumpGid = 1000;

  # Folders surfaced in Nextcloud as external storage rather than as entries
  # in the data directory. Nextcloud trusts its own index, not the
  # filesystem, so anything written to the data directory out of band stays
  # invisible. External storage is the supported path for trees that other
  # things also touch.
  externalStorage = {
    ebooks = {
      hostPath = "/dump/ebooks";
      readOnly = true;
    };
    audiobooks = {
      hostPath = "/dump/audiobooks";
      readOnly = true;
    };
    surmvault = {
      hostPath = "/dump/surmvault";
      readOnly = true;
    };
    scratch = {
      hostPath = "/dump/scratch";
      readOnly = false;
    };
  };

  containerMountPoint = name: "/mnt/${name}";

  externalStorageBindMounts = lib.mapAttrs' (
    name: mount:
    lib.nameValuePair "external-${name}" {
      mountPoint = containerMountPoint name;
      hostPath = mount.hostPath;
      isReadOnly = mount.readOnly;
    }
  ) externalStorage;

  # Idempotent: every step is a no-op once the mount exists, so the unit can
  # run on every container start.
  registerExternalStorage = pkgs.writeShellScript "nextcloud-register-external-storage" ''
    set -euo pipefail
    occ=/run/current-system/sw/bin/nextcloud-occ

    "$occ" app:enable files_external

    register() {
      local mountPoint="$1" dataDir="$2" readOnly="$3" id

      id="$("$occ" files_external:list --output=json \
        | ${pkgs.jq}/bin/jq -r --arg mp "$mountPoint" \
            '.[] | select(.mount_point == $mp) | .mount_id' \
        | ${pkgs.coreutils}/bin/head -n1)"

      if [ -z "$id" ]; then
        echo "creating external storage $mountPoint -> $dataDir"
        "$occ" files_external:create "$mountPoint" local null::null -c datadir="$dataDir"
        id="$("$occ" files_external:list --output=json \
          | ${pkgs.jq}/bin/jq -r --arg mp "$mountPoint" \
              '.[] | select(.mount_point == $mp) | .mount_id' \
          | ${pkgs.coreutils}/bin/head -n1)"
      fi

      if [ -z "$id" ]; then
        echo "failed to resolve a mount id for $mountPoint" >&2
        return 1
      fi

      "$occ" files_external:option "$id" readonly "$readOnly"
      # Notice edits made outside Nextcloud. Without this the index only
      # updates for changes Nextcloud itself made.
      "$occ" files_external:option "$id" filesystem_check_changes 1
    }

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: mount:
        "register /${name} ${containerMountPoint name} ${if mount.readOnly then "true" else "false"}"
      ) externalStorage
    )}
  '';
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
      ${pkgs.systemd}/bin/systemctl --machine=lc-nextcloud start nextcloud-external-storage.service
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
      }
      // externalStorageBindMounts;

      config = {
        system.stateVersion = "25.05";

        systemd.services = {
          nginx.wantedBy = lib.mkForce [ ];
          phpfpm-nextcloud.wantedBy = lib.mkForce [ ];
          # Registers the /dump bind mounts as external storage. Kept out of
          # multi-user.target like the rest of the stack; the host starts it
          # once the container gateway exists. A failure here leaves
          # Nextcloud itself running.
          nextcloud-external-storage = {
            description = "Register /dump folders as Nextcloud external storage";
            wantedBy = lib.mkForce [ ];
            after = [ "nextcloud-setup.service" ];
            requires = [ "nextcloud-setup.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${registerExternalStorage}";
            };
          };
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

        # Write access to /dump/scratch comes from the group, not from
        # changing any ownership on the host. The read-only trees are 0755
        # and need nothing.
        users.groups.dump-shared.gid = dumpGid;
        users.users.nextcloud.extraGroups = [ "dump-shared" ];

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
