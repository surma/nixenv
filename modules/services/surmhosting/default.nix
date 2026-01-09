{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.surmhosting;

  # Port configuration type for multi-port support
  portConfig = types.submodule {
    options = {
      port = mkOption {
        type = types.port;
        description = "Port number inside the container";
      };
      hostname = mkOption {
        type = types.str;
        description = "Hostname prefix for this port (e.g., 'llm' becomes 'llm.nexus.hosts')";
      };
      rule = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom Traefik rule (overrides hostname-based rule)";
      };
    };
  };

  exposedAppsConfigs =
    cfg.exposedApps
    |> lib.attrsToList
    |> imap0 (
      i:
      { name, value }:
      let
        isContainer = value.target.container != null;

        forwardHost = if isContainer then "10.201.${i |> toString}.2" else value.target.host;

        # Generate Traefik config for each port
        traefikConfigs =
          value.target.ports
          |> map (
            portCfg:
            let
              serviceName = "${name}-${portCfg.hostname}";
              url = "http://${forwardHost}:${toString portCfg.port}";
              routerRule =
                if portCfg.rule != null then
                  portCfg.rule
                else
                  "HostRegexp(`^${portCfg.hostname}\\.${config.services.surmhosting.hostname}`)";
            in
            {
              routers.${serviceName} = {
                rule = routerRule;
                service = serviceName;
              };
              services.${serviceName}.loadBalancer.servers = [
                { inherit url; }
              ];
            }
          );

        # Merge all Traefik configs for this app
        mergedTraefikConfig = lib.foldl' lib.recursiveUpdate { } traefikConfigs;
      in
      {
        services.traefik.dynamicConfigOptions.http = mergedTraefikConfig;

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
            localAddress = mkDefault forwardHost;
            hostAddress = mkDefault "10.201.${i |> toString}.1";
            ephemeral = mkDefault true;
            autoStart = mkDefault true;
          }
          value.target.container
        ]);
      }
    );

  targetConfig =
    { name, config, ... }:
    {
      options = {
        rule = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Custom Traefik rule for single-port mode";
        };
        target.port = mkOption {
          type = types.port;
          default = 8080;
          description = "Port for single-port mode (automatically added to target.ports)";
        };
        target.ports = mkOption {
          type = types.listOf portConfig;
          default = [ ];
          description = "List of ports to expose with their hostnames (for multi-port containers)";
        };
        target.host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Host for non-container targets";
        };
        target.container = mkOption {
          type = types.nullOr types.attrs;
          default = null;
          description = "Container configuration";
        };
      };

      # Automatically populate target.ports from target.port as default
      config.target.ports = mkDefault [
        {
          port = config.target.port;
          hostname = name;
          rule = config.rule;
        }
      ];
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
    networking.nat.internalIPs = [ "10.201.0.0/16" ];

    networking.firewall.allowedTCPPorts = [ 80 ] ++ (lib.optionals cfg.tls.enable [ 443 ]);
    networking.firewall.trustedInterfaces = [ "ve-+" ];

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
