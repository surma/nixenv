{ lib, pkgs, ... }:
let
  importConfigFile = ./firefly-import-config.json;

  fireflyImporter = pkgs.firefly-iii-data-importer;
  artisan = "${fireflyImporter}/artisan";

  importCompletedMarker = "/var/lib/firefly-iii-data-importer/import-completed-for-pipeline";
  importPipelineLog = "/var/lib/firefly-iii-data-importer/import-for-pipeline.log";

  runImport = pkgs.writeShellScript "firefly-run-import.sh" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/rm -f ${importCompletedMarker}
    set -a
    FIREFLY_III_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    VANITY_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    TRUSTED_PROXIES="**"
    FIREFLY_III_ACCESS_TOKEN="$(< /var/lib/credentials/firefly-importer/access-token.txt)"
    LUNCH_FLOW_API_KEY="$(< /var/lib/credentials/firefly-importer/lunchflow-api-key.txt)"
    IMPORT_DIR_ALLOWLIST=/nix/store
    set +a

    set +e
    ${artisan} importer:import ${importConfigFile} 2>&1 | ${pkgs.coreutils}/bin/tee ${importPipelineLog}
    import_status=''${PIPESTATUS[0]}
    set -e

    if ${pkgs.gnugrep}/bin/grep -q '^Done!$' ${importPipelineLog} && ${pkgs.gnugrep}/bin/grep -q 'Created event ImportedTransactions' ${importPipelineLog}; then
      ${pkgs.coreutils}/bin/date -u +%FT%T.%NZ > ${importCompletedMarker}
    fi

    exit "$import_status"
  '';

  stampImportCompleted = pkgs.writeShellScript "firefly-import-stamp-completed.sh" ''
    set -euo pipefail
    if [[ -e ${importCompletedMarker} ]]; then
      ${pkgs.coreutils}/bin/date -u +%FT%T.%NZ > /var/lib/firefly-importer-stamps/last-import-success
      ${pkgs.coreutils}/bin/rm -f ${importCompletedMarker}
    fi
  '';
in
{
  secrets.items.firefly-access-token = {
    target = "/var/lib/firefly-importer/access-token.txt";
    mode = "0644";
  };
  secrets.items.firefly-lunchflow-api-key = {
    target = "/var/lib/firefly-importer/lunchflow-api-key.txt";
    mode = "0644";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/firefly-importer-stamps 0755 root root -"
  ];

  services.surmhosting.services.firefly-imp.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.firefly-imp.expose.port = 80;
  services.surmhosting.services.firefly-imp.container = {
    config = {
      system.stateVersion = "25.05";

      services.firefly-iii-data-importer = {
        enable = true;
        enableNginx = true;
        virtualHost = "firefly-imp.nexus.hosts.10.0.0.2.nip.io";
        settings = {
          FIREFLY_III_URL = "http://firefly.nexus.hosts.10.0.0.2.nip.io";
          VANITY_URL = "http://firefly.nexus.hosts.10.0.0.2.nip.io";
          FIREFLY_III_ACCESS_TOKEN_FILE = "/var/lib/credentials/firefly-importer/access-token.txt";
          LUNCH_FLOW_API_KEY_FILE = "/var/lib/credentials/firefly-importer/lunchflow-api-key.txt";
          TRUSTED_PROXIES = "**";
          IMPORT_DIR_ALLOWLIST = "/nix/store";
        };
        poolConfig = {
          "request_terminate_timeout" = "1800";
        };
      };

      # Increase nginx fastcgi timeout for long-running imports (30 min)
      services.nginx.appendHttpConfig = ''
        fastcgi_read_timeout 1800s;
        fastcgi_send_timeout 1800s;
      '';

      # CLI import service — triggered manually or by timer
      systemd.services.firefly-import = {
        description = "Firefly III Data Importer - CLI Import";
        after = [ "firefly-iii-data-importer-setup.service" ];
        requires = [ "firefly-iii-data-importer-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "firefly-iii-data-importer";
          Group = "nginx";
          WorkingDirectory = fireflyImporter;
          ExecStart = runImport;
          ExecStopPost = "+${stampImportCompleted}";
          ReadWritePaths = [
            "/var/lib/firefly-iii-data-importer"
            "/var/lib/firefly-importer-stamps"
          ];
          TimeoutStartSec = "7200";
        };
      };

      # Run import twice daily (6:00 and 18:00)
      systemd.timers.firefly-import = {
        description = "Firefly III periodic import timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06,18:00:00";
          Persistent = true;
          RandomizedDelaySec = "15min";
        };
      };
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/firefly-importer";
      hostPath = "/var/lib/firefly-importer";
      isReadOnly = true;
    };

    bindMounts.stamps = {
      mountPoint = "/var/lib/firefly-importer-stamps";
      hostPath = "/var/lib/firefly-importer-stamps";
      isReadOnly = false;
    };
  };
}
