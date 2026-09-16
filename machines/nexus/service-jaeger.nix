{ ... }:
let
  ports = import ./ports.nix;
in
{
  services.surmhosting.services.jaeger = {
    backend.podman = {
      image = "cr.jaegertracing.io/jaegertracing/jaeger:2.11.0";
      ports = [
        "${toString ports.jaegerOtlpHttp}:${toString ports.jaegerOtlpHttp}"
      ];
    };

    expose.apps.jaeger = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.enable = false;
      ports = [
        {
          port = 16686;
          hostname = "jaeger";
          internalRule =
            "HostRegexp(`^jaeger\\.surmcluster`) || HostRegexp(`^jaeger\\.nexus\\.hosts`)";
        }
      ];
    };
  };
}
