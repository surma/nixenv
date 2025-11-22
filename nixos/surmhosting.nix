{
  config,
  pkgs,
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
      i:
      { name, value }:
      let
        isContainer = value.target.container != null;

        forwardPort = value.target |> lib.attrByPath [ "port" ] 8080;
        forwardHost = value.target |> lib.attrByPath [ "host" ] "localhost";

        url =
          if isContainer then
            "http://10.201.${i |> toString}.2:${forwardPort |> toString}"
          else
            "http://${forwardHost}:${forwardPort |> toString}";
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

        containers."lc-${name |> lib.substring 0 10}" = mkIf isContainer (mkMerge [
          {
            config = {
              users.users.${cfg.containeruser.name} = mkDefault {
                inherit (cfg.containeruser) uid;
                isNormalUser = true;
              };
              networking.firewall.enable = mkDefault false;
              networking.useHostResolvConf = mkDefault true;
            };

            nixpkgs = mkDefault pkgs.path;
            privateNetwork = mkDefault true;
            localAddress = mkDefault "10.201.${i |> toString}.2";
            hostAddress = mkDefault "10.201.${i |> toString}.1";
            ephemeral = mkDefault true;
            autoStart = mkDefault true;
          }
          value.target.container
        ]);
      }
    );

  targetConfig = {
    options = {
      rule = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      target.port = mkOption {
        type = types.int;
        default = 8080;
      };
      target.host = mkOption {
        type = types.str;
        default = "localhost";
      };
      target.container = mkOption {
        type = types.nullOr types.attrs;
        default = null;
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
      containeruser.name = mkOption {
        type = types.str;
        default = "containeruser";
      };
      containeruser.uid = mkOption {
        type = types.nullOr types.int;
        default = null;
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
}
