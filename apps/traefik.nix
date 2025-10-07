{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.surmhosting;

  portExposeConfig =
    cfg.portExpose
    |> lib.attrsToList
    |> map (
      { name, value }:
      {
        routers.${name} = {
          rule = "HostRegexp(`^${name}.surmcluster`)";
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { url = "http://localhost:${builtins.toString value}"; }
        ];
      }
    )
    |> lib.fold (a: b: lib.recursiveUpdate a b) { };
in
{
  options = {
    services.surmhosting = {
      enable = mkEnableOption "";
      tls.enable = mkEnableOption "";
      dashboard.enable = mkEnableOption "";
      docker.enable = mkEnableOption "";
      portExpose = mkOption {
        type = types.attrsOf types.int;
        default = { };
      };
    };
  };
  config = {

    virtualisation.podman = lib.optionalAttrs (cfg.enable) {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
    };

    services.traefik = lib.optionalAttrs (cfg.enable) {
      enable = true;
      group = "podman";
      staticConfigOptions = {
        api = {
          dashboard = cfg.dashboard.enable;
        };
        providers = lib.optionalAttrs cfg.docker.enable { docker = { }; };
        entryPoints = {
          web.address = ":80";
        }
        // (lib.optionalAttrs cfg.tls.enable {
          websecure = {
            address = ":443";
            asDefault = true;
            http.tls.certResolver = "letsencrypt";
          };
        });
        certificatesResolvers.letsencrypt = lib.optionalAttrs cfg.tls.enable {
          acme = {
            email = "surma@surma.dev";
            storage = "/var/lib/traefik/acme.json";
            httpChallenge.entryPoint = "web";
          };
        };
      };
      dynamicConfigOptions = {
        http =
          {
            routers.api = lib.optionalAttrs (cfg.dashboard.enable) {
              service = "api@internal";
              entryPoints = [ "web" ];
              rule = "HostRegexp(`^dashboard\\.surmcluster`)";
            };
          }
          |> lib.recursiveUpdate portExposeConfig;
      };
    };
  };
}
