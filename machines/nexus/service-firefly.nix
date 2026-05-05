{ pkgs, ... }:
{
  secrets.items.firefly-app-key = {
    target = "/var/lib/firefly/app-key.txt";
    mode = "0644";
  };

  services.surmhosting.services.firefly.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.firefly.expose.port = 80;
  services.surmhosting.services.firefly.container = {
    config = {
      system.stateVersion = "25.05";

      services.firefly-iii = {
        enable = true;
        enableNginx = true;
        virtualHost = "firefly.nexus.hosts.10.0.0.2.nip.io";
        dataDir = "/var/lib/firefly-iii";
        settings = {
          APP_ENV = "production";
          APP_KEY_FILE = "/var/lib/credentials/firefly/app-key.txt";
          DB_CONNECTION = "sqlite";
          APP_URL = "http://firefly.nexus.hosts.10.0.0.2.nip.io";
          TRUSTED_PROXIES = "**";
          # Force running balance off for import performance
          USE_RUNNING_BALANCE = "false";
        };
      };

      # Enable batch processing so the data importer's batch_submission flag
      # is honored — defers rules, balance recalc, webhooks, and stats to
      # the end of the batch instead of running them per-transaction.
      # Also disables running balance to avoid O(N) recalc on tag updates.
      systemd.services.firefly-iii-batch-config = {
        description = "Enable Firefly III batch processing";
        after = [ "firefly-iii-setup.service" ];
        requires = [ "firefly-iii-setup.service" ];
        requiredBy = [ "phpfpm-firefly-iii.service" ];
        before = [ "phpfpm-firefly-iii.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              db = "/var/lib/firefly-iii/storage/database/database.sqlite";
            in
            pkgs.writeShellScript "firefly-enable-batch" ''
              ${pkgs.sqlite}/bin/sqlite3 ${db} <<'EOF'
              DELETE FROM configuration WHERE name = 'enable_batch_processing' AND deleted_at IS NULL;
              INSERT INTO configuration (name, data, created_at, updated_at)
                VALUES ('enable_batch_processing', 'true', datetime('now'), datetime('now'));
              DELETE FROM configuration WHERE name = 'use_running_balance' AND deleted_at IS NULL;
              INSERT INTO configuration (name, data, created_at, updated_at)
                VALUES ('use_running_balance', 'false', datetime('now'), datetime('now'));
              EOF
            '';
        };
      };
    };

    bindMounts.state = {
      mountPoint = "/var/lib/firefly-iii";
      hostPath = "/dump/state/firefly-iii";
      isReadOnly = false;
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/firefly";
      hostPath = "/var/lib/firefly";
      isReadOnly = true;
    };
  };
}
