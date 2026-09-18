{ ... }:
{
  systemd.services.surmhosting-podman-jellyfin.unitConfig.RequiresMountsFor = [ "/dump" ];

  services.surmhosting.services.jellyfin = {
    backend.podman = {
      image = "jellyfin/jellyfin";
      podman.sdnotify = "healthy";
      # The previous container reached a 9 GiB cgroup peak during normal use.
      service.serviceConfig = {
        MemoryMax = "12G";
        MemorySwapMax = "0";
      };
      extraOptions = [
        "--memory=12g"
        # Podman treats this value as the combined RAM and swap limit.
        "--memory-swap=12g"
      ];
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
      access.mode = "allowlist";
      access.seedUsers = [ "surma" ];
      internal.access = "trusted-network";
      ports = [
        {
          port = 8096;
          hostname = "jellyfin";
          internalRule = "HostRegexp(`^jellyfin\\.surmcluster`) || HostRegexp(`^jellyfin\\.nexus\\.hosts`)";
        }
      ];
    };
  };
}
