{ ... }:
{
  services.surmhosting.services.rss.expose.port = 80;
  services.surmhosting.services.rss.container = {
    config = {
      system.stateVersion = "25.05";

      services.freshrss.enable = true;
      services.freshrss.dataDir = "/dump/state/freshrss";
      # services.freshrss.user = "containeruser";
      services.freshrss.authType = "none";
      services.freshrss.baseUrl = "http://rss.nexus.hosts.10.0.0.2.nip.io";
    };

    bindMounts.state = {
      mountPoint = "/dump/state/freshrss";
      hostPath = "/dump/state/freshrss";
      isReadOnly = false;
    };
  };
}
