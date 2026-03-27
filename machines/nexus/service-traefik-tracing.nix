{ ... }:
let
  ports = import ./ports.nix;
in
{
  services.traefik.staticConfigOptions.tracing = {
    serviceName = "traefik-nexus";
    sampleRate = 1.0;
    otlp.http.endpoint = "http://localhost:${toString ports.jaegerOtlpHttp}/v1/traces";
  };
}
