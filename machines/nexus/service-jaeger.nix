{ ... }:
let
  ports = import ./ports.nix;
in
{
  virtualisation.oci-containers.containers.jaeger = {
    serviceName = "jaeger-container";
    image = "cr.jaegertracing.io/jaegertracing/jaeger:2.11.0";
    ports = [
      "${toString ports.jaegerOtlpHttp}:${toString ports.jaegerOtlpHttp}"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.jaeger.loadbalancer.server.port" = "16686";
      # Pin the Docker-provider router to the dedicated internal entrypoint
      # so the exclusive entrypoint assignment implements the
      # trusted-network policy (auth-rework sections 3.2 and 7.2).
      "traefik.http.routers.jaeger.entrypoints" = "internal";
      "traefik.http.routers.jaeger.rule" =
        "HostRegexp(`^jaeger\\.surmcluster`) || HostRegexp(`^jaeger\\.nexus\\.hosts`)";
    };
  };
}
