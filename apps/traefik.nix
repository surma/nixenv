{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.surmhosting;

  targetConfig = {
    options = {
      rule = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      target = mkOption {
        type = types.either types.anything types.str;
      };
    };
  };

  serverExposeConfig =
    cfg.serverExpose
    |> lib.attrsToList
    |> map (
      { name, value }:
      let
        isContainer = builtins.typeOf value.target != "string";
        url =
          if isContainer then
            ""
          else
            value.target;
      in
      {services.traefik.dynamicConfigOptions.http = {
        routers.${name} = {
          rule = if value.rule == null then "HostRegexp(`^${name}.${cfg.hostname}`)" else value.rule;
          service = name;
        };

        services.${name}.loadBalancer.servers = [
          { inherit url; }
        ];
      };

        containers."lab-container-${name}" = mkIf isContainer {
          config = value.target;
        };
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
      serverExpose = mkOption {
        type = types.attrsOf (types.submodule targetConfig);
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

    services.traefik = mkMerge [
      {
      enable = true;
      group = mkIf (cfg.docker.enable) "podman";
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
          };
          # TODO: MkMerge???
          # |> lib.recursiveUpdate serverExposeConfig;
      };
    }
    serverExposeConfig
    ];
  };
}
