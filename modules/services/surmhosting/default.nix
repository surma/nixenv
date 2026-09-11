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

  # Elements that appear more than once in the list, in first-occurrence order.
  duplicates =
    list:
    let
      counts = foldl' (acc: x: acc // { ${x} = (acc.${x} or 0) + 1; }) { } list;
    in
    list |> unique |> filter (x: counts.${x} > 1);

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

  accessModes = [
    "internal"
    "public"
    "authenticated"
    "allowlist"
  ];

  appPortConfig = types.submodule {
    options = {
      port = mkOption {
        type = types.port;
        description = "Port number inside the backend";
      };
      hostname = mkOption {
        type = types.str;
        description = "Hostname prefix for this port (e.g., 'backend' becomes 'backend.nexus.hosts')";
      };
      internalRule = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom Traefik rule for the internal router (overrides the hostname-based rule)";
      };
      publicPathPrefixes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Path prefixes matched by the public router of this port.
          An empty list matches the whole domain. Path prefixes can
          never replace the domain condition.
        '';
      };
      publicPriority = mkOption {
        type = types.int;
        default = 1;
        description = "Priority of the public router of this port";
      };
    };
  };

  appConfig = types.submodule {
    options = {
      access = {
        mode = mkOption {
          type = types.enum accessModes;
          description = ''
            Access mode of this logical app: `internal` emits internal
            routes only, `public` emits public routes without
            authentication, `authenticated` requires any valid v2
            session, and `allowlist` requires a stable-ID grant or an
            admin role.
          '';
        };
        seedUsers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Usernames resolved into initial grants on first start (allowlist mode only)";
        };
      };
      internal = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to generate an internal router for this app on the dedicated internal entrypoint";
        };
        access = mkOption {
          type = types.nullOr (types.enum [ "trusted-network" ]);
          default = null;
          description = "Internal access policy. Required when internal.enable is true; only `trusted-network` is supported.";
        };
      };
      public = {
        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Primary public domain of this app. Null means no public router; it never derives a domain automatically.";
        };
        aliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional public domains that share this app's policy and session";
        };
      };
      ports = mkOption {
        type = types.listOf appPortConfig;
        default = [ ];
        description = ''
          Backend ports of this logical app. Multiple ports may share the
          same domains only inside one logical app.
        '';
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
            default = config.expose.port != null || config.expose.ports != [ ] || config.expose.apps != { };
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
          apps = mkOption {
            type = types.attrsOf appConfig;
            default = { };
            description = ''
              Explicit logical app declarations keyed by a stable app key.
              The app key selects the surm-auth policy and is never derived
              from request headers. Public routers are generated only from
              these declarations.
            '';
          };
          allowedGitHubUsers = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Legacy seed adapter. On hosts with v2 authentication or an
              appsNamespace, this list must map onto exactly one allowlist
              logical app of this service, whose seed users it extends. On
              nonmigrated hosts it keeps enabling the v1 allowlist runtime.
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
        # Read from the raw container attrs rather than the evaluated config.
        # Inspecting `options` from inside the container's own module set is
        # circular, and defining `home-manager.*` on a container that never
        # imported Home Manager is an eval error.
        hasHomeManager = hasContainer && (value.container.config or { }) ? home-manager;
        isExposed = value.expose.enable;
        containerName =
          if value.containerName != null then value.containerName else "lc-${name |> lib.substring 0 10}";
        containerUnitName = "container@${containerName}";
        localAddress = "10.201.${i |> toString}.2";
        hostAddress = "10.201.${i |> toString}.1";
        forwardHost =
          if hasContainer then
            localAddress
          else if value.host != null then
            value.host
          else
            "localhost";

        needsAuth = value.expose.allowedGitHubUsers != [ ];
        needsHostRewrite = value.expose.useTargetHost && !hasContainer && value.host != null;

        legacyTraefikConfigs =
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

        # Logical apps combine an internal router on the dedicated internal
        # entrypoint with, when a primary public domain is declared, a public
        # router on websecure. The public rule always pins the app's own
        # domains, so request headers cannot change the selected policy.
        appTraefikConfigs =
          value.expose.apps
          |> lib.attrsToList
          |> concatMap (
            entry:
            let
              appKey = entry.name;
              app = entry.value;
              isRestricted = app.access.mode == "authenticated" || app.access.mode == "allowlist";
              publicDomains = (lib.optional (app.public.domain != null) app.public.domain) ++ app.public.aliases;
              baseRule = "(${publicDomains |> map (d: "Host(`${d}`)") |> concatStringsSep " || "})";
            in
            app.ports
            |> map (
              portCfg:
              let
                serviceName = "${name}-${portCfg.hostname}";
                publicName = "apps-${appKey}-${portCfg.hostname}";
                url = "http://${forwardHost}:${toString portCfg.port}";
                pathRule =
                  if portCfg.publicPathPrefixes == [ ] then
                    ""
                  else
                    " && (${portCfg.publicPathPrefixes |> map (p: "PathPrefix(`${p}`)") |> concatStringsSep " || "})";
              in
              lib.recursiveUpdate
                {
                  routers.${serviceName} = {
                    rule =
                      if portCfg.internalRule != null then
                        portCfg.internalRule
                      else
                        "HostRegexp(`^${portCfg.hostname}\\.${cfg.hostname}`)";
                    service = serviceName;
                    entryPoints = [ "internal" ];
                  };
                  services.${serviceName}.loadBalancer.servers = [
                    { inherit url; }
                  ];
                }
                (
                  lib.optionalAttrs (app.public.domain != null) {
                    routers.${publicName} = {
                      rule = baseRule + pathRule;
                      service = publicName;
                      entryPoints = [ "websecure" ];
                      middlewares = lib.optional isRestricted "auth-${appKey}";
                      priority = portCfg.publicPriority;
                    };
                    services.${publicName}.loadBalancer.servers = [
                      { inherit url; }
                    ];
                  }
                )
            )
          );

        mergedTraefikConfig = lib.foldl' lib.recursiveUpdate { } (
          legacyTraefikConfigs ++ appTraefikConfigs
        );
      in
      {
        services.traefik = mkIf isExposed {
          dynamicConfigOptions.http = mergedTraefikConfig;
        };

        systemd.services.${containerUnitName} = mkIf hasContainer {
          wants = [
            "network-online.target"
          ]
          ++ (lib.optional config.services.tailscale.enable "tailscaled.service")
          ++ value.containerService.wants;
          after = [
            "network-online.target"
          ]
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
            autoStart = mkDefault true;
          }

          # Keep Home Manager's packages out of reach of the host's garbage
          # collector.
          #
          # Containers share the host's store and nix-daemon. Without this,
          # Home Manager installs into a user profile and registers its GC root
          # under the path the client sees (/home/<user>/...). That path does
          # not exist in the host's namespace, so the host's nix-gc prunes the
          # root as stale and then collects the profile, taking every user
          # binary with it.
          #
          # useUserPackages routes packages through users.users.<name>.packages
          # instead, which lands them in /etc/profiles/per-user/<name>. That is
          # an environment.etc entry, so it belongs to the container's system
          # closure, which the host's system closure references and roots.
          (optionalAttrs hasHomeManager {
            config.home-manager.useUserPackages = mkDefault true;
          })

          value.container
        ]);
      }
    );

  servicesWithAuth = lib.filterAttrs (
    _: service: service.expose.allowedGitHubUsers != [ ]
  ) cfg.services;

  # v2 authentication is explicitly enabled. It no longer depends on the
  # presence of legacy seed lists.
  v2AuthEnabled = cfg.auth.enable;
  legacyAuthEnabled = !v2AuthEnabled && servicesWithAuth != { };

  # A migrated host declares an apps namespace and must express every HTTP
  # exposure through explicit logical apps.
  v2RoutingActive = cfg.appsNamespace != null;
  v2Active = v2AuthEnabled || v2RoutingActive;

  allApps =
    serviceEntries
    |> concatMap (
      { name, value }:
      value.expose.apps
      |> lib.attrsToList
      |> map (entry: {
        service = name;
        serviceValue = value;
        key = entry.name;
        app = entry.value;
      })
    );

  appKeys = allApps |> map (a: a.key);

  restrictedApps =
    allApps |> filter (a: a.app.access.mode == "authenticated" || a.app.access.mode == "allowlist");

  appDomainEntries =
    allApps
    |> concatMap (
      { key, app, ... }:
      ((lib.optional (app.public.domain != null) app.public.domain) ++ app.public.aliases)
      |> map (domain: {
        inherit domain;
        inherit key;
      })
    );
  duplicateAppDomains = appDomainEntries |> map (a: a.domain) |> duplicates;

  appRouterNames =
    allApps
    |> concatMap (
      {
        service,
        key,
        app,
        ...
      }:
      app.ports
      |> concatMap (
        portCfg:
        [ "${service}-${portCfg.hostname}" ]
        ++ (lib.optional (app.public.domain != null) "apps-${key}-${portCfg.hostname}")
      )
    );

  hasInternalApps = allApps |> any (a: a.app.internal.enable);
  internalEntrypointEnabled = hasInternalApps || (v2RoutingActive && cfg.dashboard.enable);

  tlsChallenge = cfg.tls.challenge;
  certResolverName = if tlsChallenge != null then "cloudflare" else "letsencrypt";

  acmeDomains =
    (lib.optional (cfg.appsNamespace != null) { main = "*.${cfg.appsNamespace}"; })
    ++ (
      cfg.tls.certDomains
      |> map (d: { main = d.main; } // (lib.optionalAttrs (d.sans != [ ]) { inherit (d) sans; }))
    );

  # The session cookie is set for the parent domain; every public app domain
  # must live underneath it or single sign-on silently breaks.
  cookieBase = removePrefix "." cfg.auth.cookieDomain;
  domainCoveredByCookie = domain: domain == cookieBase || hasSuffix ".${cookieBase}" domain;

  authDomainsList = (lib.optional (cfg.auth.domain != null) cfg.auth.domain) ++ cfg.auth.aliases;
  authRouterRule = authDomainsList |> map (d: "Host(`${d}`)") |> concatStringsSep " || ";

  # Per-app forward-auth middlewares. The middleware URL pins the logical app
  # key from Nix; the policy is never selected from the Host header or
  # forwarded metadata.
  appAuthMiddlewares =
    restrictedApps
    |> map (
      { key, ... }:
      nameValuePair "auth-${key}" {
        forwardAuth = {
          address = "http://10.202.0.2:8080/auth?app=${key}";
          trustForwardHeader = false;
          authRequestHeaders = [ "Cookie" ];
          authResponseHeaders = [
            "X-Auth-Request-User"
            "X-Auth-Request-Email"
          ];
        };
      }
    )
    |> listToAttrs;

  # The v2 auth configuration lists every logical app with its mode,
  # domains, and seed users (legacy seed adapters included).
  v2AuthApps =
    allApps
    |> map (
      {
        serviceValue,
        key,
        app,
        ...
      }:
      let
        adapterUsers = serviceValue.expose.allowedGitHubUsers;
        seedUsers =
          if app.access.mode == "allowlist" then
            lib.unique (app.access.seedUsers ++ adapterUsers)
          else
            app.access.seedUsers;
      in
      nameValuePair key {
        mode = app.access.mode;
        domains = (lib.optional (app.public.domain != null) app.public.domain) ++ app.public.aliases;
        seedUsers = seedUsers;
      }
    )
    |> listToAttrs;

  serviceAssertions =
    serviceEntries
    |> concatMap (
      { name, value }:
      let
        hasLegacyExposure = value.expose.port != null || value.expose.ports != [ ];
        allowlistApps =
          value.expose.apps
          |> lib.attrsToList
          |> filter (entry: entry.value.access.mode == "allowlist")
          |> length;
      in
      [
        {
          assertion = !(value.container != null && value.host != null);
          message = "surmhosting service `${name}` cannot set both `container` and `host`.";
        }
        {
          assertion = (!value.expose.enable) || value.expose.ports != [ ] || value.expose.apps != { };
          message = "surmhosting service `${name}` has exposure enabled but no expose.port/expose.ports/expose.apps configured.";
        }
        {
          assertion = value.expose.allowedGitHubUsers == [ ] || value.expose.enable;
          message = "surmhosting service `${name}` configures expose.allowedGitHubUsers but is not exposed.";
        }
        {
          assertion = !value.expose.useTargetHost || value.expose.enable;
          message = "surmhosting service `${name}` configures expose.useTargetHost but is not exposed.";
        }
        {
          assertion = !(value.expose.apps != { } && hasLegacyExposure);
          message = "surmhosting service `${name}` mixes legacy expose.port/expose.ports with expose.apps. Migrate the legacy exposure to a logical app.";
        }
        {
          assertion =
            !(v2RoutingActive && value.expose.enable && value.expose.apps == { } && hasLegacyExposure);
          message = "surmhosting service `${name}` keeps a legacy HTTP exposure on a migrated host (appsNamespace is set). Declare explicit expose.apps for it.";
        }
        {
          assertion = !(v2Active && value.expose.allowedGitHubUsers != [ ] && allowlistApps != 1);
          message = "surmhosting service `${name}` sets expose.allowedGitHubUsers, which seeds exactly one allowlist logical app (found ${toString allowlistApps}).";
        }
      ]
    );

  appAssertions = [
    {
      assertion = allUnique appKeys;
      message = "surmhosting: duplicate logical app keys: ${concatStringsSep ", " (duplicates appKeys)}";
    }
    {
      assertion = allApps |> all (a: builtins.match "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?" a.key != null);
      message = "surmhosting: logical app keys must be DNS labels (invalid: ${
        concatStringsSep ", " (
          appKeys |> filter (k: builtins.match "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?" k == null)
        )
      })";
    }
    {
      assertion = duplicateAppDomains == [ ];
      message = "surmhosting: the same public domain is declared by multiple logical apps: ${concatStringsSep ", " duplicateAppDomains}";
    }
    {
      assertion = allUnique appRouterNames;
      message = "surmhosting: generated router names collide: ${concatStringsSep ", " (duplicates appRouterNames)}";
    }
    {
      assertion = !v2RoutingActive || tlsChallenge == "dns-01";
      message = "surmhosting: appsNamespace requires tls.challenge = \"dns-01\" for wildcard certificates.";
    }
    {
      assertion = tlsChallenge == null || cfg.tls.enable;
      message = "surmhosting: tls.challenge requires tls.enable.";
    }
    {
      assertion = tlsChallenge != "dns-01" || cfg.tls.dnsEnvironmentFile != null;
      message = "surmhosting: tls.challenge = \"dns-01\" requires tls.dnsEnvironmentFile.";
    }
    {
      assertion =
        tlsChallenge == null
        || (
          (config.services.traefik.staticConfigOptions.entryPoints.web.forwardedHeaders.trustedIPs or [ ])
          == [ ]
          &&
            (config.services.traefik.staticConfigOptions.entryPoints.websecure.forwardedHeaders.trustedIPs
              or [ ]
            ) == [ ]
          && !(config.services.traefik.staticConfigOptions.entryPoints.web.forwardedHeaders.insecure or false)
          && !(config.services.traefik.staticConfigOptions.entryPoints.websecure.forwardedHeaders.insecure
            or false
          )
        );
      message = "surmhosting: TLS challenge mode forbids forwarded-header trust. Remove forwardedHeaders.trustedIPs/insecure overrides from the public web and websecure entrypoints.";
    }
    {
      assertion = !v2AuthEnabled || cfg.tls.enable;
      message = "surmhosting: auth.enable requires tls.enable because the auth service is only reachable over HTTPS.";
    }
  ]
  ++ (
    allApps
    |> concatMap (
      {
        service,
        key,
        app,
        ...
      }:
      let
        mode = app.access.mode;
      in
      [
        {
          assertion = app.ports != [ ];
          message = "surmhosting: logical app `${key}` on service `${service}` declares no ports.";
        }
        {
          assertion = app.internal.enable -> app.internal.access != null;
          message = "surmhosting: logical app `${key}` on service `${service}` must set internal.access when internal.enable is true.";
        }
        {
          assertion = mode != "internal" || app.public.domain == null;
          message = "surmhosting: logical app `${key}` on service `${service}` is internal-only and must not declare a public domain.";
        }
        {
          assertion = mode != "internal" || app.public.aliases == [ ];
          message = "surmhosting: logical app `${key}` on service `${service}` is internal-only and must not declare public aliases.";
        }
        {
          assertion = mode != "internal" || app.access.seedUsers == [ ];
          message = "surmhosting: logical app `${key}` on service `${service}` is internal-only and must not declare seed users.";
        }
        {
          assertion = mode == "internal" || app.public.domain != null;
          message = "surmhosting: logical app `${key}` on service `${service}` uses mode `${mode}` and must declare a primary public domain.";
        }
        {
          assertion = mode == "allowlist" || app.access.seedUsers == [ ];
          message = "surmhosting: logical app `${key}` on service `${service}` declares seed users, which are only valid in allowlist mode.";
        }
        {
          assertion = !(mode == "authenticated" || mode == "allowlist") || v2AuthEnabled;
          message = "surmhosting: logical app `${key}` on service `${service}` requires authentication. Set services.surmhosting.auth.enable = true.";
        }
        {
          assertion = app.public.domain == null || cfg.tls.enable;
          message = "surmhosting: logical app `${key}` on service `${service}` declares a public domain. Public routers require tls.enable.";
        }
        {
          assertion = app.public.domain == null || !(builtins.elem app.public.domain app.public.aliases);
          message = "surmhosting: logical app `${key}` on service `${service}` repeats its primary domain in its aliases.";
        }
        {
          assertion = duplicates app.public.aliases == [ ];
          message = "surmhosting: logical app `${key}` on service `${service}` repeats an alias: ${concatStringsSep ", " (duplicates app.public.aliases)}";
        }
        {
          assertion = !v2AuthEnabled || app.public.domain == null || domainCoveredByCookie app.public.domain;
          message = "surmhosting: logical app `${key}` on service `${service}` uses a public domain${
            optionalString (app.public.domain != null) " `${app.public.domain}`"
          } that the session cookie domain `${cfg.auth.cookieDomain}` does not cover.";
        }
        {
          assertion =
            !v2AuthEnabled || app.public.aliases == [ ] || all domainCoveredByCookie app.public.aliases;
          message = "surmhosting: logical app `${key}` on service `${service}` uses an alias that the session cookie domain `${cfg.auth.cookieDomain}` does not cover.";
        }
      ]
    )
  );

  # ---- Legacy v1 authentication (nonmigrated hosts) ----
  # Preserved byte-for-byte: nonmigrated host generations keep the v1
  # runtime, and the v2 binary rejects this configuration shape with a
  # migration error.
  legacyAuthConfig = {
    containers."surm-auth" = mkIf legacyAuthEnabled {
      autoStart = true;
      privateNetwork = true;
      localAddress = "10.202.0.2";
      hostAddress = "10.202.0.1";
      ephemeral = true;

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
            version = 1;
            package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.surm-auth;
            baseUrl = "https://${cfg.auth.domain}";

            github.clientIdFile = "/var/lib/secrets/github-client-id";
            github.clientSecretFile = "/var/lib/secrets/github-client-secret";

            session.cookieName = "_surm_auth";
            session.cookieDomain = cfg.auth.cookieDomain;
            session.cookieSecretFile = "/var/lib/secrets/cookie-secret";
            session.duration = cfg.auth.sessionDuration;

            apps = lib.mapAttrs (_: service: {
              mode = "allowlist";
              domains = [ ];
              seedUsers = service.expose.allowedGitHubUsers;
            }) servicesWithAuth;
          };

          networking.firewall.enable = false;
        };
    };

    systemd.services."container@surm-auth" = mkIf legacyAuthEnabled {
      serviceConfig = mkMerge [
        (mkIf (cfg.containerLimits.memoryMax != null) {
          MemoryMax = mkDefault cfg.containerLimits.memoryMax;
        })
        (mkIf (cfg.containerLimits.memorySwapMax != null) {
          MemorySwapMax = mkDefault cfg.containerLimits.memorySwapMax;
        })
      ];
    };

    services.traefik = mkIf legacyAuthEnabled {
      dynamicConfigOptions.http = {
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
      tls.challenge = mkOption {
        type = types.nullOr (
          types.enum [
            "http-01"
            "dns-01"
          ]
        );
        default = null;
        description = ''
          ACME challenge for the certificate resolver. Null keeps the legacy
          `letsencrypt` HTTP-01 resolver untouched. When set, the resolver is
          named `cloudflare`, public entrypoints distrust forwarded headers,
          and port 80 redirects explicitly to HTTPS.
        '';
      };
      tls.dnsEnvironmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Environment file with the DNS provider credentials (for example
          CF_DNS_API_TOKEN). Required for the DNS-01 challenge and passed to
          services.traefik.environmentFiles.
        '';
      };
      tls.certDomains = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              main = mkOption {
                type = types.str;
                description = "Primary certificate domain";
              };
              sans = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Subject alternative names";
              };
            };
          }
        );
        default = [ ];
        description = "Additional certificates issued by the resolver, for example exact names below a wildcard namespace.";
      };
      tls.email = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      tls.acmeFile = mkOption {
        type = types.str;
        default = "/var/lib/traefik/acme.json";
      };
      appsNamespace = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Domain namespace of public logical apps (for example
          `apps.surma.technology`). Setting it marks the host as migrated:
          every HTTP exposure must be an explicit logical app, app keys are
          validated as DNS labels, and `*.<namespace>` joins the certificate
          list. It does not publish any port by itself.
        '';
      };
      internalPort = mkOption {
        type = types.port;
        default = 8081;
        description = "Port of the dedicated internal HTTP entrypoint.";
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
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable the surm-auth v2 container and its forward-auth middlewares, independent of any legacy seed list.";
        };
        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Canonical domain for the auth service (e.g., auth.surma.technology)";
        };
        aliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional auth domains served by the same login and callback validator.";
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
        policyFile = mkOption {
          type = types.str;
          default = "/var/lib/surm-auth/policy.json";
          description = "Path of the persistent policy file inside the auth container.";
        };
        auditFile = mkOption {
          type = types.str;
          default = "/var/lib/surm-auth/audit.log";
          description = "Path of the audit log file inside the auth container.";
        };
        bootstrapAdmins = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                provider = mkOption {
                  type = types.str;
                  default = "github";
                  description = "Identity provider name";
                };
                id = mkOption {
                  type = types.str;
                  description = "Stable provider ID of the administrator (never a username)";
                };
              };
            }
          );
          default = [ ];
          description = "Nix-owned administrator identities reasserted by the auth service at startup.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (legacyAuthEnabled || v2AuthEnabled) -> cfg.auth.domain != null;
        message = ''
          surmhosting authentication is enabled, but services.surmhosting.auth.domain is not set.
        '';
      }
      {
        assertion = (legacyAuthEnabled || v2AuthEnabled) -> cfg.auth.github.clientIdFile != null;
        message = ''
          surmhosting authentication is enabled, but services.surmhosting.auth.github.clientIdFile is not set.
        '';
      }
      {
        assertion = (legacyAuthEnabled || v2AuthEnabled) -> cfg.auth.github.clientSecretFile != null;
        message = ''
          surmhosting authentication is enabled, but services.surmhosting.auth.github.clientSecretFile is not set.
        '';
      }
      {
        assertion = (legacyAuthEnabled || v2AuthEnabled) -> cfg.auth.cookieSecretFile != null;
        message = ''
          surmhosting authentication is enabled, but services.surmhosting.auth.cookieSecretFile is not set.
        '';
      }
    ]
    ++ serviceAssertions
    ++ appAssertions;

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
              web = {
                address = ":80";
              }
              // (lib.optionalAttrs (tlsChallenge != null) {
                forwardedHeaders = {
                  insecure = false;
                  trustedIPs = [ ];
                };
                http.redirections.entryPoint = {
                  to = "websecure";
                  scheme = "https";
                  permanent = true;
                };
              });
            }
            // (lib.optionalAttrs cfg.tls.enable {
              websecure = {
                address = ":443";
                asDefault = true;
                http.tls.certResolver = certResolverName;
              }
              // (lib.optionalAttrs (tlsChallenge != null) {
                forwardedHeaders = {
                  insecure = false;
                  trustedIPs = [ ];
                };
              });
            })
            // (lib.optionalAttrs internalEntrypointEnabled {
              internal.address = ":${toString cfg.internalPort}";
            });
            certificatesResolvers =
              if tlsChallenge != null then
                lib.optionalAttrs cfg.tls.enable {
                  cloudflare.acme =
                    { }
                    // (lib.optionalAttrs (cfg.tls.email != null) { email = cfg.tls.email; })
                    // {
                      storage = cfg.tls.acmeFile;
                    }
                    // (
                      if tlsChallenge == "dns-01" then
                        { dnsChallenge.provider = "cloudflare"; }
                      else
                        { httpChallenge.entryPoint = "web"; }
                    )
                    // (lib.optionalAttrs (acmeDomains != [ ]) { domains = acmeDomains; });
                }
              else
                lib.optionalAttrs cfg.tls.enable {
                  letsencrypt.acme =
                    { }
                    // (lib.optionalAttrs (cfg.tls.email != null) { email = cfg.tls.email; })
                    // {
                      storage = cfg.tls.acmeFile;
                      httpChallenge.entryPoint = "web";
                    };
                };
          };
          dynamicConfigOptions = {
            http = {
              routers.api = lib.optionalAttrs (cfg.dashboard.enable) {
                service = "api@internal";
                entryPoints = if v2RoutingActive then [ "internal" ] else [ "web" ];
                rule = "HostRegexp(`^dashboard\\.surmcluster`)";
              };
            };
          };
        }
      ]
      ++ (managedServiceConfigs |> map (service: service.services.traefik))
      ++ (lib.optional legacyAuthEnabled legacyAuthConfig.services.traefik)
      ++ (lib.optional v2AuthEnabled {
        dynamicConfigOptions.http = {
          routers."surm-auth" = {
            rule = authRouterRule;
            service = "surm-auth";
            entryPoints = [ "websecure" ];
          };

          services."surm-auth".loadBalancer.servers = [
            {
              url = "http://10.202.0.2:8080";
            }
          ];

          middlewares = appAuthMiddlewares;
        };
      })
      ++ (lib.optional (tlsChallenge == "dns-01") {
        environmentFiles = [ cfg.tls.dnsEnvironmentFile ];
      })
    );

    systemd.services = mkMerge (
      (managedServiceConfigs |> map (service: service.systemd.services))
      ++ (lib.optional legacyAuthEnabled legacyAuthConfig.systemd.services)
      ++ (lib.optional v2AuthEnabled {
        "container@surm-auth" = {
          # A failed decryption must prevent container startup.
          requires = [ "secrets.service" ];
          after = [ "secrets.service" ];

          serviceConfig = mkMerge [
            (mkIf (cfg.containerLimits.memoryMax != null) {
              MemoryMax = mkDefault cfg.containerLimits.memoryMax;
            })
            (mkIf (cfg.containerLimits.memorySwapMax != null) {
              MemorySwapMax = mkDefault cfg.containerLimits.memorySwapMax;
            })
          ];
        };
      })
      ++ (lib.optional (tlsChallenge == "dns-01") {
        traefik = {
          requires = [ "secrets.service" ];
          after = [ "secrets.service" ];
        };
      })
    );

    systemd.tmpfiles.rules = lib.optionals v2AuthEnabled [
      # Dedicated persistent private-state parent and credential directory
      # for the auth container (auth-rework sections 6.2 and 6.3).
      "d /var/lib/surm-auth-state 0700 root root -"
      "d /var/lib/surm-auth-credentials 0700 root root -"
    ];

    containers = mkMerge (
      (managedServiceConfigs |> map (service: service.containers))
      ++ (lib.optional legacyAuthEnabled legacyAuthConfig.containers)
      ++ (lib.optional v2AuthEnabled {
        "surm-auth" = {
          autoStart = true;
          privateNetwork = true;
          localAddress = "10.202.0.2";
          hostAddress = "10.202.0.1";
          ephemeral = true;

          bindMounts = {
            # Decrypted credentials; root-only on the host. Container PID 1
            # reads them through LoadCredential.
            secrets = {
              mountPoint = "/var/lib/secrets";
              hostPath = "/var/lib/surm-auth-credentials";
              isReadOnly = true;
            };
            # Dedicated persistent private-state parent for this container
            # only. The DynamicUser StateDirectory manages
            # /var/lib/private/surm-auth inside the container.
            state = {
              mountPoint = "/var/lib/private";
              hostPath = "/var/lib/surm-auth-state";
              isReadOnly = false;
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
                version = 2;
                package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.surm-auth;
                baseUrl = "https://${cfg.auth.domain}";
                authDomains = authDomainsList;

                github.clientIdFile = "/var/lib/secrets/github-client-id";
                github.clientSecretFile = "/var/lib/secrets/github-client-secret";

                session.cookieDomain = cfg.auth.cookieDomain;
                session.cookieSecretFile = "/var/lib/secrets/cookie-secret";
                session.duration = cfg.auth.sessionDuration;

                policy.file = cfg.auth.policyFile;
                audit.file = cfg.auth.auditFile;

                bootstrapAdmins = cfg.auth.bootstrapAdmins;

                apps = v2AuthApps;
              };

              networking.firewall.enable = false;
            };
        };
      })
    );
  };
}
