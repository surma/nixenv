{ pkgs, ... }:
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
  containerAdminPasswordFile = "/var/lib/nextcloud-secrets/admin-pass";
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
      ${pkgs.coreutils}/bin/install -d -m 0700 -o postgres -g postgres \
        ${stateDirectory}/postgresql

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

  # This key follows zz-immich, which preserves every existing Surmhosting
  # container and Podman address.
  services.surmhosting.services."zz-nextcloud" = {
    backend."nixos-container" = {
      name = "lc-nextcloud";

      service = {
        requires = [ "nextcloud-state.service" ];
        after = [ "nextcloud-state.service" ];
        serviceConfig.MemoryMax = "8G";
      };

      bindMounts = {
        home = {
          mountPoint = "/var/lib/nextcloud";
          hostPath = "${stateDirectory}/home";
          isReadOnly = false;
        };
        postgresql = {
          mountPoint = "/var/lib/postgresql";
          hostPath = "${stateDirectory}/postgresql";
          isReadOnly = false;
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

        users.users.nextcloud.uid = nextcloudUid;
        users.groups.nextcloud.gid = nextcloudUid;

        services.nextcloud = {
          enable = true;
          package = pkgs.nextcloud33;
          hostName = domain;
          https = true;

          database.createLocally = true;
          config = {
            dbtype = "pgsql";
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
