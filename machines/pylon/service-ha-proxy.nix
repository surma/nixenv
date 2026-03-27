{ ... }:
{
  services.traefik.dynamicConfigOptions.http = {
    routers.ha = {
      rule = "Host(`ha.surma.technology`)";
      service = "ha";
    };
    services.ha.loadBalancer.servers = [
      {
        url = "http://100.97.65.42:8123";
      }
    ];
  };
}
