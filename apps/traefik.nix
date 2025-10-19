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
          rule = "HostRegexp(`^${name}.${cfg.hostname}.hosts`)";
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
      externalInterface = mkOption {
        type = types.str;
      };
      tls.enable = mkEnableOption "";
      tls.email = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      tls.acmeFile = mkOption {
        type = types.str;
        default = "/var/lib/traefik/acme.json";
      };
      dashboard.enable = mkEnableOption "";
      docker.enable = mkEnableOption "";
      hostname = mkOption {
        type = types.str;
      };
      portExpose = mkOption {
        type = types.attrsOf types.int;
        default = { };
      };
    };
  };
  config = mkIf cfg.enable {
    virtualisation.podman = lib.optionalAttrs (cfg.docker.enable) {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
    };

    networking.nat.enable = true;
    networking.nat.externalInterface = cfg.externalInterface;
    networking.nat.internalInterfaces = [ "ve-+" ];

    services.traefik = {
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
            email = cfg.tls.email;
            storage = cfg.tls.acmeFile;
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
