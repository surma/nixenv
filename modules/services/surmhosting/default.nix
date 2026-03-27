{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib;
let
  cfg = config.services.surmhosting;

  portConfig = types.submodule {
    options = {
      port = mkOption {
        type = types.port;
        description = "Port number inside the backend";
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

  containerServiceConfig = types.submodule {
    options = {
      wants = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional systemd Wants= dependencies for the container unit.";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional systemd After= dependencies for the container unit.";
      };
      serviceConfig = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional systemd serviceConfig for the generated container@ unit.";
      };
    };
  };

  serviceConfig =
    { name, config, ... }:
    {
      options = {
        host = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Host for non-container backends. Defaults to localhost when exposing a local host service.";
        };
        container = mkOption {
          type = types.nullOr types.attrs;
          default = null;
          description = "NixOS container configuration.";
        };
        containerName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Override the generated NixOS container name.";
        };
        containerService = mkOption {
          type = containerServiceConfig;
          default = { };
          description = "Overrides for the generated container@ systemd unit.";
        };
        expose = {
          enable = mkOption {
            type = types.bool;
            default = config.expose.port != null || config.expose.ports != [ ];
            description = "Whether to expose this service via Traefik.";
          };
          rule = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Custom Traefik rule for single-port mode.";
          };
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Port for single-port mode (automatically added to expose.ports).";
          };
          ports = mkOption {
            type = types.listOf portConfig;
            default = [ ];
            description = "List of ports to expose with their hostnames.";
          };
          allowedGitHubUsers = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              List of GitHub usernames allowed to access this service.
              If set, OAuth2 authentication is automatically enabled.
            '';
            example = [
              "surma"
              "stimhub"
            ];
          };
          useTargetHost = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to rewrite the Host header to match host when forwarding requests.";
          };
        };
      };

      config = mkIf (config.expose.port != null) {
        expose.ports = mkDefault [
          {
            port = config.expose.port;
            hostname = name;
            rule = config.expose.rule;
          }
        ];
      };
    };

  serviceEntries = cfg.services |> lib.attrsToList;

  managedServiceConfigs =
    serviceEntries
    |> imap0 (
      i:
      { name, value }:
      let
        hasContainer = value.container != null;
        isExposed = value.expose.enable;
        containerName = if value.containerName != null then value.containerName else "lc-${name |> lib.substring 0 10}";
        containerUnitName = "container@${containerName}";
        localAddress = "10.201.${i |> toString}.2";
        hostAddress = "10.201.${i |> toString}.1";
        forwardHost = if hasContainer then localAddress else if value.host != null then value.host else "localhost";

        needsAuth = value.expose.allowedGitHubUsers != [ ];
        needsHostRewrite = value.expose.useTargetHost && !hasContainer && value.host != null;

        traefikConfigs =
          value.expose.ports
          |> map (
            portCfg:
            let
              serviceName = "${name}-${portCfg.hostname}";
              url = "http://${forwardHost}:${toString portCfg.port}";
              routerRule =
                if portCfg.rule != null then
                  portCfg.rule
                else
                  "HostRegexp(`^${portCfg.hostname}\\.${cfg.hostname}`)";
              middlewareList =
                (lib.optional needsAuth "auth-${name}") ++ (lib.optional needsHostRewrite "host-rewrite-${name}");
            in
            {
              routers.${serviceName} = {
                rule = routerRule;
                service = serviceName;
                middlewares = middlewareList;
                entryPoints = if cfg.tls.enable then [ "websecure" ] else [ "web" ];
              };
              services.${serviceName}.loadBalancer.servers = [
                { inherit url; }
              ];
            }
            // (lib.optionalAttrs needsHostRewrite {
              middlewares."host-rewrite-${name}" = {
                headers.customRequestHeaders.Host = value.host;
              };
            })
          );

        mergedTraefikConfig = lib.foldl' lib.recursiveUpdate { } traefikConfigs;
      in
      {
        services.traefik = mkIf isExposed {
          dynamicConfigOptions.http = mergedTraefikConfig;
        };

        systemd.services.${containerUnitName} = mkIf hasContainer {
          wants = [ "network-online.target" ]
            ++ (lib.optional config.services.tailscale.enable "tailscaled.service")
            ++ value.containerService.wants;
          after = [ "network-online.target" ]
            ++ (lib.optional config.services.tailscale.enable "tailscaled.service")
            ++ value.containerService.after;

          serviceConfig = mkMerge [
            (mkIf (cfg.containerLimits.memoryMax != null) {
              MemoryMax = mkDefault cfg.containerLimits.memoryMax;
            })
            (mkIf (cfg.containerLimits.memorySwapMax != null) {
              MemorySwapMax = mkDefault cfg.containerLimits.memorySwapMax;
            })
            value.containerService.serviceConfig
          ];
        };

        containers.${containerName} = mkIf hasContainer (mkMerge [
          {
            config = {
              users.users.${cfg.containeruser.name} = mkDefault {
                inherit (cfg.containeruser) uid;
                isNormalUser = true;
              };
              networking.firewall.enable = mkDefault false;
              networking.useHostResolvConf = mkForce false;
              networking.nameservers = mkDefault [ "8.8.8.8" ];
            };

            nixpkgs = mkDefault pkgs.path;
            privateNetwork = mkDefault true;
            localAddress = mkDefault localAddress;
            hostAddress = mkDefault hostAddress;
            ephemeral = mkDefault true;
            extraFlags = mkAfter [ "--link-journal=host" ];
            autoStart = mkDefault true;
          }
          value.container
        ]);
      }
    );

  servicesWithAuth = lib.filterAttrs (_: service: service.expose.allowedGitHubUsers != [ ]) cfg.services;
  authEnabled = servicesWithAuth != { };

  serviceAssertions = serviceEntries |> concatMap (
    { name, value }:
    [
      {
        assertion = !(value.container != null && value.host != null);
        message = "surmhosting service `${name}` cannot set both `container` and `host`.";
      }
      {
        assertion = (!value.expose.enable) || value.expose.ports != [ ];
        message = "surmhosting service `${name}` has exposure enabled but no expose.port/expose.ports configured.";
      }
      {
        assertion = value.expose.allowedGitHubUsers == [ ] || value.expose.enable;
        message = "surmhosting service `${name}` configures expose.allowedGitHubUsers but is not exposed.";
      }
      {
        assertion = !value.expose.useTargetHost || value.expose.enable;
        message = "surmhosting service `${name}` configures expose.useTargetHost but is not exposed.";
      }
    ]
  );

  surmAuthConfig = {
    containers."surm-auth" = mkIf authEnabled {
      autoStart = true;
      privateNetwork = true;
      localAddress = "10.202.0.2";
      hostAddress = "10.202.0.1";
      ephemeral = true;
      extraFlags = mkAfter [ "--link-journal=host" ];

      bindMounts = {
        secrets = {
          mountPoint = "/var/lib/secrets";
          hostPath = "/var/lib/surm-auth";
          isReadOnly = true;
        };
      };

      config =
        { ... }:
        {
          imports = [ ../surm-auth ];

          system.stateVersion = "25.05";

          networking.useHostResolvConf = mkForce false;
          networking.nameservers = [ "8.8.8.8" ];

          services.surm-auth = {
            enable = true;
            package = inputs.self.packages.${pkgs.system}.surm-auth;
            baseUrl = "https://${cfg.auth.domain}";

            github.clientIdFile = "/var/lib/secrets/github-client-id";
            github.clientSecretFile = "/var/lib/secrets/github-client-secret";

            session.cookieDomain = cfg.auth.cookieDomain;
            session.cookieSecretFile = "/var/lib/secrets/cookie-secret";
            session.duration = cfg.auth.sessionDuration;

            apps = lib.mapAttrs (_: service: {
              allowed_users = service.expose.allowedGitHubUsers;
            }) servicesWithAuth;
          };

          networking.firewall.enable = false;
        };
    };

    systemd.services."container@surm-auth" = mkIf authEnabled {
      serviceConfig = mkMerge [
        (mkIf (cfg.containerLimits.memoryMax != null) {
          MemoryMax = mkDefault cfg.containerLimits.memoryMax;
        })
        (mkIf (cfg.containerLimits.memorySwapMax != null) {
          MemorySwapMax = mkDefault cfg.containerLimits.memorySwapMax;
        })
      ];
    };

    services.traefik.dynamicConfigOptions.http = mkIf authEnabled {
      routers."surm-auth" = {
        rule = "Host(`${cfg.auth.domain}`)";
        service = "surm-auth";
        entryPoints = [ "websecure" ];
      };

      services."surm-auth".loadBalancer.servers = [
        {
          url = "http://10.202.0.2:8080";
        }
      ];

      middlewares = lib.mapAttrs' (
        name: _service:
        lib.nameValuePair "auth-${name}" {
          forwardAuth = {
            address = "http://10.202.0.2:8080/auth?app=${name}";
            trustForwardHeader = true;
            authResponseHeaders = [
              "X-Auth-Request-User"
              "X-Auth-Request-Email"
            ];
            authRequestHeaders = [
              "Cookie"
              "X-Forwarded-Method"
              "X-Forwarded-Proto"
              "X-Forwarded-Host"
              "X-Forwarded-Uri"
            ];
          };
        }
      ) servicesWithAuth;
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
      containerLimits = {
        memoryMax = mkOption {
          type = types.nullOr types.str;
          default = "4G";
          description = "Default MemoryMax limit applied to all surmhosting container units (container@lc-*).";
        };
        memorySwapMax = mkOption {
          type = types.nullOr types.str;
          default = "0";
          description = "Default MemorySwapMax limit applied to all surmhosting container units (container@lc-*).";
        };
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
      services = mkOption {
        type = types.attrsOf (types.submodule serviceConfig);
        default = { };
      };
      auth = {
        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Domain for the auth service (e.g., auth.surma.technology)";
        };
        github = {
          clientIdFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing GitHub OAuth Client ID";
          };
          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing GitHub OAuth Client Secret";
          };
        };
        cookieSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to file containing cookie encryption secret";
        };
        cookieDomain = mkOption {
          type = types.str;
          default = ".${cfg.hostname}";
          description = "Cookie domain for SSO across all apps";
        };
        sessionDuration = mkOption {
          type = types.str;
          default = "168h";
          description = "Session duration (default: 168h = 7 days)";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions =
      [
        {
          assertion = authEnabled -> cfg.auth.domain != null;
          message = ''
            OAuth2 authentication is enabled (some services have expose.allowedGitHubUsers),
            but services.surmhosting.auth.domain is not set.
          '';
        }
        {
          assertion = authEnabled -> cfg.auth.github.clientIdFile != null;
          message = ''
            OAuth2 authentication is enabled (some services have expose.allowedGitHubUsers),
            but services.surmhosting.auth.github.clientIdFile is not set.
          '';
        }
        {
          assertion = authEnabled -> cfg.auth.github.clientSecretFile != null;
          message = ''
            OAuth2 authentication is enabled (some services have expose.allowedGitHubUsers),
            but services.surmhosting.auth.github.clientSecretFile is not set.
          '';
        }
        {
          assertion = authEnabled -> cfg.auth.cookieSecretFile != null;
          message = ''
            OAuth2 authentication is enabled (some services have expose.allowedGitHubUsers),
            but services.surmhosting.auth.cookieSecretFile is not set.
          '';
        }
      ]
      ++ serviceAssertions;

    virtualisation.podman = lib.optionalAttrs (cfg.docker.enable) {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
    };

    networking.nat.enable = true;
    networking.nat.externalInterface = cfg.externalInterface;
    networking.nat.internalIPs = [
      "10.201.0.0/16"
      "10.202.0.0/16"
    ];

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
      ++ (managedServiceConfigs |> map (service: service.services.traefik))
      ++ (lib.optional authEnabled surmAuthConfig.services.traefik)
    );

    systemd.services = mkMerge (
      (managedServiceConfigs |> map (service: service.systemd.services))
      ++ (lib.optional authEnabled surmAuthConfig.systemd.services)
    );

    containers = mkMerge (
      (managedServiceConfigs |> map (service: service.containers))
      ++ (lib.optional authEnabled surmAuthConfig.containers)
    );
  };
}
