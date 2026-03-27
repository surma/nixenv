{ ... }:
{
  services.traefik.dynamicConfigOptions.http = {
    routers.music = {
      rule = "Host(`music.surma.technology`)";
      service = "music";
    };
    services.music.loadBalancer = {
      servers = [
        {
          url = "http://music.nexus.hosts.100.83.198.90.nip.io";
        }
      ];
      passHostHeader = false;
    };
  };
}
