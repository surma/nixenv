{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.surmhosting;

  exposedAppsConfigs =
    cfg.exposedApps
    |> lib.attrsToList
    |> imap0 (
      idx:
      { name, value }:
      let
        isBasicForward = (value.target |> lib.attrByPath [ "port" ] null |> builtins.typeOf) == "int";
        isContainer = !isBasicForward;

        forwardPort = value.target |> lib.attrByPath [ "port" ] 8080;
        forwardHost = value.target |> lib.attrByPath [ "host" ] "localhost";

        url =
          if isContainer then
            "http://10.200.${i}.2:${port |> builtins.toString}"
          else
            "http://${forwardHost}:${forwardPort |> builtins.toString}" |> lib.traceVal;
      in
      {
        services.traefik.dynamicConfigOptions.http = {
          routers.${name} = {
            rule =
              if value.rule == null then
                "HostRegexp(`^${name}.${config.services.surmhosting.hostname}`)"
              else
                value.rule;
            service = name;
          };

          services.${name}.loadBalancer.servers = [
            { inherit url; }
          ];
        };

        containers."lab-container-${name}" = mkIf isContainer (
          lib.optionalAttrs isContainer {
            config = value.target.config;

            privateNetwork = true;
            localAddress = "10.200.${i}.2";
            hostAddress = "10.200.${i}.1";
            ephemeral = true;
            autoStart = true;
          }
        );
      }
    );

  targetConfig = {
    options = {
      rule = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      target = mkOption {
        type = types.anything;
      };
    };
  };
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
      exposedApps = mkOption {
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

    services.traefik = mkMerge (
      [
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
            http = {
              routers.api = lib.optionalAttrs (cfg.dashboard.enable) {
                service = "api@internal";
                entryPoints = [ "web" ];
                rule = "HostRegexp(`^dashboard\\.surmcluster`)";
              };
            };
          };
        }
      ]
      ++ (exposedAppsConfigs |> map (cfg: cfg.services.traefik))
    );
    containers = mkMerge (exposedAppsConfigs |> map (cfg: cfg.containers));
  };
  # |> lib.recursiveUpdate exposedAppsConfig);
}
