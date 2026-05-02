{ ... }:
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
