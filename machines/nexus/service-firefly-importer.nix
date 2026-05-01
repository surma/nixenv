{ lib, ... }:
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
    };

    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/firefly-importer";
      hostPath = "/var/lib/firefly-importer";
      isReadOnly = true;
    };
  };
}
