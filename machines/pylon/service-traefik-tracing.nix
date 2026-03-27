{ ... }:
let
  ports = import ./ports.nix;
in
{
  services.traefik.staticConfigOptions.tracing = {
    serviceName = "traefik-edge";
    sampleRate = 1.0;
    otlp.http.endpoint = "http://100.83.198.90:${toString ports.remoteJaegerOtlpHttp}/v1/traces";
  };
}
