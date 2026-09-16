{ ... }:
{
  services.surmhosting.services.jellyfin = {
    backend.podman = {
      image = "jellyfin/jellyfin";
      podman.sdnotify = "healthy";
      volumes = [
        "/dump/state/jellyfin/config:/config"
        "/dump/state/jellyfin/cache:/cache"
        "/dump/TV:/media/TV"
        "/dump/Movies:/media/Movies"
        "/dump/audiobooks:/media/audiobooks"
        "/dump/lol:/media/lol"
      ];
    };

    expose.apps.jellyfin = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.enable = false;
      ports = [
        {
          port = 8096;
          hostname = "jellyfin";
          internalRule =
            "HostRegexp(`^jellyfin\\.surmcluster`) || HostRegexp(`^jellyfin\\.nexus\\.hosts`)";
        }
      ];
    };
  };
}
