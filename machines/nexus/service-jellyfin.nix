{ ... }:
{
  virtualisation.oci-containers.containers.jellyfin = {
    serviceName = "jellyfin-container";
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
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.jellyfin.loadbalancer.server.port" = "8096";
      "traefik.http.routers.jellyfin.rule" =
        "HostRegexp(`^jellyfin\\.surmcluster`) || HostRegexp(`^jellyfin\\.nexus\\.hosts`)";
      # Docker-provider routers are audited like every other router: pin
      # Jellyfin to the dedicated internal entrypoint so its exclusive
      # entrypoint assignment implements the trusted-network policy
      # (auth-rework sections 3.2 and 7.2).
      "traefik.http.routers.jellyfin.entrypoints" = "internal";
    };
  };
}
