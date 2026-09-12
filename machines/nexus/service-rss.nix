{ ... }:
{
  # FreshRSS has authType = "none"; the public route stays behind the
  # allowlist while the trusted internal route remains available.
  services.surmhosting.services.rss.expose.apps.rss = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    ports = [
      {
        port = 80;
        hostname = "rss";
      }
    ];
  };
  services.surmhosting.services.rss.container = {
    config = {
      system.stateVersion = "25.05";

      services.freshrss.enable = true;
      services.freshrss.dataDir = "/dump/state/freshrss";
      # services.freshrss.user = "containeruser";
      services.freshrss.authType = "none";
      services.freshrss.baseUrl = "http://rss.nexus.hosts.10.0.0.2.nip.io:8081";
    };

    bindMounts.state = {
      mountPoint = "/dump/state/freshrss";
      hostPath = "/dump/state/freshrss";
      isReadOnly = false;
    };
  };
}
