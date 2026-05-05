{ lib, pkgs, ... }:
let
  importConfigFile = ./firefly-import-config.json;

  fireflyImporter = pkgs.firefly-iii-data-importer;
  artisan = "${fireflyImporter}/artisan";

  runImport = pkgs.writeShellScript "firefly-run-import.sh" ''
    set -euo pipefail
    set -a
    FIREFLY_III_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    VANITY_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    TRUSTED_PROXIES="**"
    FIREFLY_III_ACCESS_TOKEN="$(< /var/lib/credentials/firefly-importer/access-token.txt)"
    LUNCH_FLOW_API_KEY="$(< /var/lib/credentials/firefly-importer/lunchflow-api-key.txt)"
    IMPORT_DIR_ALLOWLIST=/nix/store
    set +a
    exec ${artisan} importer:import ${importConfigFile}
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

      # CLI import service — triggered manually via systemd, no timeout issues
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
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/firefly-importer";
      hostPath = "/var/lib/firefly-importer";
      isReadOnly = true;
    };
  };
}
