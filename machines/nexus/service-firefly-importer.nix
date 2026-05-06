{ lib, pkgs, ... }:
let
  importConfigFile = ./firefly-import-config.json;

  fireflyImporter = pkgs.firefly-iii-data-importer;
  artisan = "${fireflyImporter}/artisan";

  fireflyUrl = "http://firefly.nexus.hosts.10.0.0.2.nip.io";

  runImport = pkgs.writeShellScript "firefly-run-import.sh" ''
    set -uo pipefail
    set -a
    FIREFLY_III_URL="${fireflyUrl}"
    VANITY_URL="${fireflyUrl}"
    TRUSTED_PROXIES="**"
    FIREFLY_III_ACCESS_TOKEN="$(< /var/lib/credentials/firefly-importer/access-token.txt)"
    LUNCH_FLOW_API_KEY="$(< /var/lib/credentials/firefly-importer/lunchflow-api-key.txt)"
    IMPORT_DIR_ALLOWLIST=/nix/store
    set +a

    # Run the import.  The importer exits non-zero when any transaction
    # is a duplicate, which is expected during daily runs. Capture the
    # exit code so the post-import fixup still runs.
    ${artisan} importer:import ${importConfigFile} || \
      echo "Import exited $? (expected when duplicates are present)"

    # Convert inter-account payments to transfers (see fixTransfers)
    ${fixTransfers}
  '';

  # Post-import: convert inter-account withdrawals to transfers.
  # Firefly III's convert_withdrawal rule action is broken in 6.5.x,
  # so we use the API directly.  Maps expense-account names (as sent
  # by Lunch Flow) to asset-account IDs in Firefly III.
  fixTransfers = pkgs.writeShellScript "firefly-fix-transfers.sh" ''
    set -euo pipefail
    FIREFLY_URL="${fireflyUrl}"
    TOKEN="$(< /var/lib/credentials/firefly-importer/access-token.txt)"
    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"

    auth() { echo "Authorization: Bearer $TOKEN"; }

    convert() {
      local expense_name="$1" dest_id="$2" src_id="$3"
      local page=1

      while true; do
        resp=$($CURL -sf \
          -H "$(auth)" -H "Accept: application/json" \
          "$FIREFLY_URL/api/v1/accounts/$src_id/transactions?type=withdrawal&limit=50&page=$page")

        ids=$($JQ -r --arg name "$expense_name" \
          '.data[] | select(.attributes.transactions[0].destination_name == $name) | .id' <<< "$resp")

        for tid in $ids; do
          echo "Converting txn $tid: $expense_name -> asset $dest_id"
          $CURL -sf \
            -H "$(auth)" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -X PUT "$FIREFLY_URL/api/v1/transactions/$tid" \
            -d "{\"transactions\":[{\"type\":\"transfer\",\"source_id\":\"$src_id\",\"destination_id\":\"$dest_id\"}]}" \
            -o /dev/null || echo "  WARN: failed to convert $tid"
        done

        total=$($JQ '.meta.pagination.total_pages' <<< "$resp")
        [ "$page" -ge "$total" ] && break
        page=$((page + 1))
      done
    }

    # Lloyds Bank (6) -> Amex Platinum (4)
    convert "AMERICAN EXPRESS" 4 6
    # Lloyds Bank (6) -> Halifax Credit Card (5)
    convert "HALIFAX" 5 6

    echo "Transfer conversion complete."
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
          ReadWritePaths = [ "/var/lib/firefly-iii-data-importer" ];
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
  };
}
