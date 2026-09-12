/**
  Focused fixtures for the surmhosting and surm-auth modules.

  Most fixtures evaluate a minimal NixOS host that imports the real shared
  modules and assert on the generated Traefik configuration, the auth
  container contract, and the rendered surm-auth v2 configuration. Invalid
  declarations must produce the intended assertion message. These are
  evaluation fixtures: they prove configuration values, not runtime
  behavior.

  Two fixtures execute real programs: `unitDependencyRuntime` runs
  `systemd-analyze verify` against the generated unit dependency section,
  and `legacyV1Rejected` runs the packaged surm-auth v2 binary against the
  legacy v1 configuration schema and asserts the rejection.

  Import with a flake for full fidelity:

      let
        f = builtins.getFlake (toString ./.);
        pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      in
      import ./modules/services/surmhosting/tests.nix {
        inherit pkgs;
        inputs = f.inputs // { self = f; };
      }

  Without `inputs`, the fixtures evaluate the repository directly from the
  working tree.
*/
{
  pkgs,
  inputs ? null,
  lib ? pkgs.lib,
}:
let
  # Repository root, resolved relative to this file. Used to evaluate the
  # surm-auth package without requiring a flake `self` input.
  repoRoot = ./../../..;

  flakeInputs =
    if inputs != null then
      inputs
    else
      {
        nixpkgs = {
          lib = pkgs.lib;
          outPath = pkgs.path;
        };
        self = {
          packages.${pkgs.stdenv.hostPlatform.system}.surm-auth =
            pkgs.callPackage (repoRoot + "/packages/surm-auth")
              {
                inputs.self = repoRoot;
              };
        };
      };

  evalConfig =
    modules:
    if flakeInputs.nixpkgs ? lib && (flakeInputs.nixpkgs.lib ? nixosSystem) then
      flakeInputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        modules = modules;
        specialArgs = {
          inputs = flakeInputs;
        };
      }
    else
      import (pkgs.path + "/nixos/lib/eval-config.nix") {
        system = pkgs.stdenv.hostPlatform.system;
        modules = modules;
        specialArgs = {
          inputs = flakeInputs;
        };
      };

  evalHost =
    {
      surmhosting ? { },
      extraModules ? [ ],
    }:
    evalConfig (
      [
        ./default.nix
        (
          { lib, ... }:
          {
            networking.hostName = "surmhosting-fixture";
            system.stateVersion = "25.05";
            services.surmhosting = lib.mkMerge [
              {
                enable = lib.mkDefault true;
                hostname = lib.mkDefault "nexus";
                externalInterface = lib.mkDefault "eth0";
              }
              surmhosting
            ];
          }
        )
      ]
      ++ extraModules
    );

  expect = ok: msg: { inherit ok msg; };

  expectEq =
    actual: expected: msg:
    expect (actual == expected)
      "${msg} — expected ${lib.generators.toPretty { } expected}, got ${
        lib.generators.toPretty { } actual
      }";

  # Only force the messages of FAILED assertions. Forcing every message
  # trips over upstream assertions whose message interpolation is broken
  # for the passing case (filesystems.nix `cycle`).
  failedAssertionMessages =
    host: host.config.assertions |> lib.filter (a: !a.assertion) |> lib.map (a: a.message);

  expectMsg =
    host: needle: msg:
    let
      messages = failedAssertionMessages host;
    in
    expect (messages |> lib.any (m: lib.hasInfix needle m))
      "${msg} — no failed assertion message contains `${needle}`; failed assertions were: ${
        messages |> lib.concatStringsSep " | "
      }";

  # The failed assertion messages of a host, for assertions about the
  # message content itself.
  expectMessages = failedAssertionMessages;

  noSurmhostingAssertions =
    host: msg:
    let
      messages = failedAssertionMessages host;
    in
    expect (
      !(messages |> lib.any (m: lib.hasInfix "surmhosting" m))
    ) "${msg} — unexpected surmhosting assertions: ${messages |> lib.concatStringsSep " | "}";

  # Lines of one INI section of a rendered systemd unit text. Used to prove
  # WHERE systemd reads a generated dependency from: top-level `[Unit]`
  # dependencies are enforced, `[Service]` dependency keys are ignored.
  iniSectionLines =
    text: wanted:
    let
      lines = lib.splitString "\n" text;
      isHeader = line: lib.hasPrefix "[" line && lib.hasSuffix "]" line;
      headerName = line: builtins.substring 1 (builtins.stringLength line - 2) line;
      step =
        { current, found }:
        line:
        let
          trimmed = lib.trim line;
        in
        if trimmed == "" then
          {
            inherit current found;
          }
        else if isHeader trimmed then
          {
            current = headerName trimmed;
            inherit found;
          }
        else if current == wanted then
          {
            inherit current;
            found = found ++ [ trimmed ];
          }
        else
          {
            inherit current found;
          };
    in
    (lib.foldl' step {
      current = null;
      found = [ ];
    } lines).found;

  checkFixture =
    name: conditions:
    let
      failures = conditions |> lib.filter (c: !c.ok);
      failureText = failures |> lib.map (c: "  - ${c.msg}") |> lib.concatStringsSep "\n";
    in
    lib.throwIfNot (failures == [ ]) "surmhosting fixture `${name}` failed:\n${failureText}" (
      pkgs.runCommand "surmhosting-fixture-${name}" { } "touch $out"
    );

  authCommon = {
    appsNamespace = "apps.surma.technology";
    auth.enable = true;
    auth.domain = "auth.surma.technology";
    auth.aliases = [ "auth.apps.surma.technology" ];
    auth.cookieDomain = ".surma.technology";
    auth.github.clientIdFile = "/var/lib/surm-auth-credentials/github-client-id";
    auth.github.clientSecretFile = "/var/lib/surm-auth-credentials/github-client-secret";
    auth.cookieSecretFile = "/var/lib/surm-auth-credentials/cookie-secret";
    auth.bootstrapAdmins = [
      {
        provider = "github";
        id = "12345678";
      }
    ];
  };

  # Migrated host covering the plan's initial public inventory shapes:
  # HedgeDoc's two ports under one app, Brain's private/public split, one
  # app per LLM port with its own alias, an allowlisted app, and the
  # legacy seed adapter.
  inventoryHost = evalHost {
    surmhosting = {
      appsNamespace = "apps.surma.technology";
      tls.enable = true;
      tls.challenge = "dns-01";
      tls.dnsEnvironmentFile = "/var/lib/surmedge-credentials/cloudflare.env";
      tls.email = "surma@surma.dev";
      internalPort = 8081;
      dashboard.enable = true;
      docker.enable = true;
    }
    // authCommon;
    extraModules = [
      (
        { lib, ... }:
        {
          services.surmhosting.services = {
            svc-hedgedoc.host = "10.201.0.2";
            svc-hedgedoc.expose.apps.hedgedoc2 = {
              access.mode = "allowlist";
              access.seedUsers = [ "surma" ];
              internal.access = "trusted-network";
              public.aliases = [ "hedgedoc.surma.technology" ];
              ports = [
                {
                  port = 3000;
                  hostname = "backend";
                  publicPathPrefixes = [
                    "/realtime"
                    "/api"
                  ];
                  publicPriority = 100;
                }
                {
                  port = 3001;
                  hostname = "frontend";
                }
              ];
            };

            svc-brain.host = "10.201.1.2";
            svc-brain.expose.apps.brain = {
              access.mode = "allowlist";
              access.seedUsers = [ "surma" ];
              internal.access = "trusted-network";
              public.aliases = [ "brain.surma.technology" ];
              ports = [
                {
                  port = 8080;
                  hostname = "brain-serve";
                }
              ];
            };
            svc-brain.expose.apps.public-brain = {
              access.mode = "public";
              internal.access = "trusted-network";
              public.aliases = [ "public-brain.surma.technology" ];
              ports = [
                {
                  port = 8081;
                  hostname = "public-brain";
                }
              ];
            };

            svc-llm.host = "10.201.2.2";
            svc-llm.expose.apps.proxy-llm = {
              access.mode = "public";
              internal.access = "trusted-network";
              public.aliases = [ "proxy.llm.surma.technology" ];
              ports = [
                {
                  port = 4000;
                  hostname = "proxy-llm";
                }
              ];
            };
            svc-llm.expose.apps.key-llm = {
              access.mode = "public";
              internal.access = "trusted-network";
              public.aliases = [ "key.llm.surma.technology" ];
              ports = [
                {
                  port = 8080;
                  hostname = "key-llm";
                }
              ];
            };
            svc-llm.expose.apps.vendors-llm = {
              access.mode = "public";
              internal.access = "trusted-network";
              public.aliases = [ "vendors.llm.surma.technology" ];
              ports = [
                {
                  port = 4001;
                  hostname = "vendors-llm";
                }
              ];
            };

            svc-admin.host = "localhost";
            svc-admin.expose.apps.admin = {
              access.mode = "allowlist";
              access.seedUsers = [ "surma" ];
              internal.access = "trusted-network";
              ports = [
                {
                  port = 8092;
                  hostname = "admin";
                }
              ];
            };

            svc-dump.host = "10.201.3.2";
            svc-dump.expose.allowedGitHubUsers = [
              "surma"
              "friend"
            ];
            svc-dump.expose.apps.dump = {
              access.mode = "allowlist";
              access.seedUsers = [ "explicit" ];
              internal.access = "trusted-network";
              public.aliases = [ "dump.surma.technology" ];
              ports = [
                {
                  port = 80;
                  hostname = "dump";
                }
              ];
            };
          };
        }
      )
    ];
  };

  http = inventoryHost.config.services.traefik.dynamicConfigOptions.http;
  static = inventoryHost.config.services.traefik.staticConfigOptions;

  routers = checkFixture "logical-app-routers" ([
    (noSurmhostingAssertions inventoryHost "logical-app-routers")
    (expectEq (lib.attrNames http.routers) [
      "api"
      "apps-admin-admin"
      "apps-brain-brain-serve"
      "apps-dump-dump"
      "apps-hedgedoc2-backend"
      "apps-hedgedoc2-frontend"
      "apps-key-llm-key-llm"
      "apps-proxy-llm-proxy-llm"
      "apps-public-brain-public-brain"
      "apps-vendors-llm-vendors-llm"
      "surm-auth"
      "svc-admin-admin"
      "svc-brain-brain-serve"
      "svc-brain-public-brain"
      "svc-dump-dump"
      "svc-hedgedoc-backend"
      "svc-hedgedoc-frontend"
      "svc-llm-key-llm"
      "svc-llm-proxy-llm"
      "svc-llm-vendors-llm"
    ] "generated router names")
    (expectEq http.routers."apps-hedgedoc2-backend" {
      rule = "(Host(`hedgedoc2.apps.surma.technology`) || Host(`hedgedoc.surma.technology`)) && (PathPrefix(`/realtime`) || PathPrefix(`/api`))";
      service = "apps-hedgedoc2-backend";
      entryPoints = [ "websecure" ];
      middlewares = [ "auth-hedgedoc2" ];
      priority = 100;
    } "public backend router")
    (expectEq http.routers."apps-hedgedoc2-frontend" {
      rule = "(Host(`hedgedoc2.apps.surma.technology`) || Host(`hedgedoc.surma.technology`))";
      service = "apps-hedgedoc2-frontend";
      entryPoints = [ "websecure" ];
      middlewares = [ "auth-hedgedoc2" ];
      priority = 1;
    } "public frontend router")
    (expectEq http.routers."svc-hedgedoc-backend" {
      rule = "HostRegexp(`^backend\\.nexus`)";
      service = "svc-hedgedoc-backend";
      entryPoints = [ "internal" ];
    } "internal backend router uses the dedicated internal entrypoint and no auth middleware")
    (expectEq http.routers."surm-auth" {
      rule = "Host(`auth.surma.technology`) || Host(`auth.apps.surma.technology`)";
      service = "surm-auth";
      entryPoints = [ "websecure" ];
    } "auth router covers the canonical domain and its alias")
    (expectEq http.services."apps-brain-brain-serve".loadBalancer.servers [
      { url = "http://10.201.1.2:8080"; }
    ] "public brain service backend")
    (expectEq http.services."svc-hedgedoc-frontend".loadBalancer.servers [
      { url = "http://10.201.0.2:3001"; }
    ] "internal frontend service backend")
    (expectEq http.routers."apps-admin-admin" {
      rule = "(Host(`admin.apps.surma.technology`))";
      service = "apps-admin-admin";
      entryPoints = [ "websecure" ];
      middlewares = [ "auth-admin" ];
      priority = 1;
    } "the allowlisted app gets a derived public router")
    (expectEq (
      http.middlewares ? "auth-public-brain"
    ) false "public apps must not get an auth middleware")
    (expectEq static.entryPoints.web.forwardedHeaders {
      insecure = false;
      trustedIPs = [ ];
    } "the public HTTP entrypoint distrusts forwarded headers")
    (expectEq static.entryPoints.web.http.redirections.entryPoint {
      to = "websecure";
      scheme = "https";
      permanent = true;
    } "port 80 redirects explicitly to HTTPS")
    (expectEq static.entryPoints.websecure.forwardedHeaders.trustedIPs [ ]
      "the public HTTPS entrypoint trusts no forwarded-header sources"
    )
    (expectEq static.entryPoints.websecure.http.tls.certResolver "cloudflare"
      "public routers use the challenge resolver"
    )
    (expectEq static.certificatesResolvers.cloudflare.acme.dnsChallenge.provider "cloudflare"
      "the resolver uses the Cloudflare DNS-01 challenge"
    )
    (expectEq static.certificatesResolvers.cloudflare.acme.domains [
      { main = "*.apps.surma.technology"; }
    ] "the apps namespace wildcard joins the certificate list")
    (expectEq (inventoryHost.config.services.traefik.environmentFiles |> map toString) [
      "/var/lib/surmedge-credentials/cloudflare.env"
    ] "the DNS-01 challenge consumes the Cloudflare credential environment file")
    (expectEq inventoryHost.config.systemd.services.traefik.requires [
      "secrets.service"
    ] "traefik requires the secrets service for the DNS credentials")
  ]);

  authKeys = checkFixture "fixed-auth-keys" (
    let
      middlewares = http.middlewares;
    in
    [
      (expectEq middlewares."auth-hedgedoc2" {
        forwardAuth = {
          address = "http://10.202.0.2:8080/auth?app=hedgedoc2";
          trustForwardHeader = false;
          authRequestHeaders = [ "Cookie" ];
          authResponseHeaders = [
            "X-Auth-Request-User"
            "X-Auth-Request-Email"
          ];
        };
      } "forward-auth middleware pins the logical app key in a fixed URL")
      (expectEq middlewares."auth-dump".forwardAuth.address "http://10.202.0.2:8080/auth?app=dump"
        "the legacy seed adapter's middleware uses the logical app key"
      )
      (expectEq (lib.attrNames (middlewares |> lib.filterAttrs (n: _: lib.hasPrefix "auth-" n))) [
        "auth-admin"
        "auth-brain"
        "auth-dump"
        "auth-hedgedoc2"
      ] "one middleware per restricted app key")
    ]
  );

  # A migrated host behind a plain TCP forwarder (no DNS provider
  # credentials on this host): the wildcard joins the ACME domain list only
  # under DNS-01. Under HTTP-01 the resolver uses the HTTP challenge on the
  # web entrypoint, adds no environment files, and depends on no secrets
  # service; Traefik derives one exact certificate per router Host rule.
  http01Migrated = checkFixture "http01-migrated" (
    let
      host = evalHost {
        surmhosting = {
          appsNamespace = "apps.surma.technology";
          tls.enable = true;
          tls.challenge = "http-01";
          tls.email = "surma@surma.dev";
          dashboard.enable = true;
        }
        // authCommon;
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.svc-hedgedoc = {
                host = "10.201.0.2";
                expose.apps.hedgedoc2 = {
                  access.mode = "allowlist";
                  access.seedUsers = [ "surma" ];
                  internal.access = "trusted-network";
                  public.aliases = [ "hedgedoc.surma.technology" ];
                  ports = [
                    {
                      port = 3001;
                      hostname = "frontend";
                    }
                  ];
                };
              };
            }
          )
        ];
      };
      http = host.config.services.traefik.dynamicConfigOptions.http;
      static = host.config.services.traefik.staticConfigOptions;
      acme = static.certificatesResolvers.letsencrypt.acme;
    in
    [
      (noSurmhostingAssertions host "http01-migrated")
      (expectEq acme.httpChallenge.entryPoint "web"
        "the resolver uses the HTTP-01 challenge on the web entrypoint"
      )
      (expectEq (acme ? dnsChallenge) false "the resolver uses no DNS-01 challenge")
      (expectEq (acme.domains or [ ]
      ) [ ] "an HTTP-01 migrated host must not contain a wildcard ACME domain for the apps namespace")
      (expectEq (
        host.config.services.traefik.environmentFiles |> map toString
      ) [ ] "the HTTP-01 challenge adds no environment files")
      (expectEq (builtins.elem "secrets.service" host.config.systemd.services.traefik.requires) false
        "traefik does not require the secrets service under HTTP-01"
      )
      (expectEq (builtins.elem "secrets.service" host.config.systemd.services.traefik.after) false
        "traefik does not order after the secrets service under HTTP-01"
      )
      (expectEq static.entryPoints.web.http.redirections.entryPoint {
        to = "websecure";
        scheme = "https";
        permanent = true;
      } "port 80 still redirects explicitly to HTTPS under HTTP-01")
      (expectEq static.entryPoints.web.forwardedHeaders {
        insecure = false;
        trustedIPs = [ ];
      } "the public HTTP entrypoint still distrusts forwarded headers")
      (expectEq static.entryPoints.websecure.forwardedHeaders {
        insecure = false;
        trustedIPs = [ ];
      } "the public HTTPS entrypoint still distrusts forwarded headers")
      (expectEq static.entryPoints.websecure.http.tls.certResolver "letsencrypt"
        "public routers use the HTTP-01 resolver, so Traefik requests exact certificates"
      )
      (expectEq http.routers."apps-hedgedoc2-frontend".rule
        "(Host(`hedgedoc2.apps.surma.technology`) || Host(`hedgedoc.surma.technology`))"
        "the public router pins the exact app domains, from which Traefik derives one certificate per domain"
      )
      (expectEq http.routers."surm-auth".rule
        "Host(`auth.surma.technology`) || Host(`auth.apps.surma.technology`)"
        "the auth router pins the exact auth domains, from which Traefik derives one certificate per domain"
      )
    ]
  );

  surmAuthContainer = inventoryHost.config.containers."surm-auth";
  surmAuthService = surmAuthContainer.config.services.surm-auth;

  expectedV2Config = {
    version = 2;
    server = {
      address = "0.0.0.0:8080";
      base_url = "https://auth.surma.technology";
      auth_domains = [
        "auth.surma.technology"
        "auth.apps.surma.technology"
      ];
    };
    session = {
      cookie_name = "_surm_auth2";
      cookie_domain = ".surma.technology";
      cookie_secret_file = "/run/credentials/surm-auth.service/cookie-secret";
      cookie_secure = true;
      duration = "168h";
    };
    policy.file = "/var/lib/surm-auth/policy.json";
    audit.file = "/var/lib/surm-auth/audit.log";
    providers.github = {
      client_id_file = "/run/credentials/surm-auth.service/github-client-id";
      client_secret_file = "/run/credentials/surm-auth.service/github-client-secret";
    };
    bootstrap_admins = [
      {
        provider = "github";
        id = "12345678";
      }
    ];
    apps = {
      hedgedoc2 = {
        mode = "allowlist";
        domains = [
          "hedgedoc2.apps.surma.technology"
          "hedgedoc.surma.technology"
        ];
        seed_users = [ "surma" ];
      };
      brain = {
        mode = "allowlist";
        domains = [
          "brain.apps.surma.technology"
          "brain.surma.technology"
        ];
        seed_users = [ "surma" ];
      };
      public-brain = {
        mode = "public";
        domains = [
          "public-brain.apps.surma.technology"
          "public-brain.surma.technology"
        ];
        seed_users = [ ];
      };
      proxy-llm = {
        mode = "public";
        domains = [
          "proxy-llm.apps.surma.technology"
          "proxy.llm.surma.technology"
        ];
        seed_users = [ ];
      };
      key-llm = {
        mode = "public";
        domains = [
          "key-llm.apps.surma.technology"
          "key.llm.surma.technology"
        ];
        seed_users = [ ];
      };
      vendors-llm = {
        mode = "public";
        domains = [
          "vendors-llm.apps.surma.technology"
          "vendors.llm.surma.technology"
        ];
        seed_users = [ ];
      };
      admin = {
        mode = "allowlist";
        domains = [
          "admin.apps.surma.technology"
        ];
        seed_users = [ "surma" ];
      };
      dump = {
        mode = "allowlist";
        domains = [
          "dump.apps.surma.technology"
          "dump.surma.technology"
        ];
        seed_users = [
          "explicit"
          "surma"
          "friend"
        ];
      };
    };
  };

  v2Config = checkFixture "v2-config-rendering" [
    (expectEq (lib.hasAttr "surm-auth" inventoryHost.config.containers) true
      "the v2 auth container exists without any legacy seed list driving it"
    )
    (expectEq surmAuthContainer.bindMounts.state {
      mountPoint = "/var/lib/private";
      hostPath = "/var/lib/surm-auth-state";
      isReadOnly = false;
    } "the auth container bind-mounts the dedicated persistent state directory to /var/lib/private")
    (expectEq surmAuthContainer.bindMounts.secrets {
      mountPoint = "/var/lib/secrets";
      hostPath = "/var/lib/surm-auth-credentials";
      isReadOnly = true;
    } "the auth container bind-mounts decrypted credentials read-only")
    (expectEq (surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.LoadCredential) [
      "github-client-id:/var/lib/secrets/github-client-id"
      "github-client-secret:/var/lib/secrets/github-client-secret"
      "cookie-secret:/var/lib/secrets/cookie-secret"
    ] "the in-container auth unit receives the three credentials through LoadCredential")
    (expectEq (
      surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.ExecStart
      |> lib.hasInfix "surm-auth --config"
    ) true "the auth unit starts the packaged binary with a generated config file")
    (expectEq
      [
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.DynamicUser
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.StateDirectory
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.StateDirectoryMode
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.ProtectSystem
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.PrivateTmp
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.ProtectHome
        surmAuthContainer.config.systemd.services."surm-auth".serviceConfig.NoNewPrivileges
      ]
      [
        true
        "surm-auth"
        "0700"
        "strict"
        true
        true
        true
      ]
      "the in-container auth unit implements the DynamicUser state contract"
    )
    (expectEq surmAuthService.finalConfig expectedV2Config
      "the rendered v2 configuration matches the Go app contract exactly"
    )
    (expectEq (lib.hasAttr "oauth" surmAuthService.finalConfig) false
      "the v2 configuration contains no legacy oauth key"
    )
    (expectEq inventoryHost.config.systemd.services."container@surm-auth".requires [
      "secrets.service"
    ] "the auth container unit requires secrets.service")
    (expectEq (builtins.elem "secrets.service"
      inventoryHost.config.systemd.services."container@surm-auth".after
    ) true "the auth container unit orders after secrets.service")
    (expectEq (lib.all (rule: builtins.elem rule inventoryHost.config.systemd.tmpfiles.rules) [
      "d /var/lib/surm-auth-state 0700 root root -"
      "d /var/lib/surm-auth-credentials 0700 root root -"
    ]) true "the host creates the persistent state and credential directories")
  ];

  # Host mirroring the Nexus LLM proxy contract: a container service whose
  # generated `container@` unit must depend on secrets.service, plus the v2
  # auth container for the runtime verification below.
  mkLlmHost =
    containerService:
    evalHost {
      surmhosting = {
        tls.enable = true;
      }
      // authCommon;
      extraModules = [
        (
          { lib, ... }:
          {
            services.surmhosting.services.llm-proxy = {
              inherit containerService;
              container.config.system.stateVersion = "25.05";
              expose.apps.proxy-llm = {
                access.mode = "public";
                internal.access = "trusted-network";
                public.aliases = [ "proxy.llm.surma.technology" ];
                ports = [
                  {
                    port = 4000;
                    hostname = "proxy-llm";
                  }
                ];
              };
            };
          }
        )
      ];
    };

  # The corrected declaration shape: top-level `requires`.
  llmFixed = mkLlmHost {
    wants = [ "secrets.service" ];
    requires = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  # The rejected pre-fix shape: `serviceConfig.Requires` only, which the
  # `[Service]` section does not interpret as a dependency.
  llmServiceShape = mkLlmHost {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig.Requires = [ "secrets.service" ];
  };

  llmUnitName = "container@lc-llm-proxy";
  llmUnitText = llmFixed.config.systemd.units."${llmUnitName}.service".text;
  llmServiceShapeUnitText = llmServiceShape.config.systemd.units."${llmUnitName}.service".text;
  authUnitText = llmFixed.config.systemd.units."container@surm-auth.service".text;

  llmDependency = checkFixture "llm-dependency-contract" [
    (noSurmhostingAssertions llmFixed "llm-dependency-contract")
    (expectEq llmFixed.config.systemd.services.${llmUnitName}.requires [
      "secrets.service"
    ] "the generated LLM container unit requires secrets.service at the top level")
    (expectEq (builtins.elem "secrets.service"
      llmFixed.config.systemd.services.${llmUnitName}.wants
    ) true "the generated LLM unit wants secrets.service")
    (expectEq (builtins.elem "secrets.service"
      llmFixed.config.systemd.services.${llmUnitName}.after
    ) true "the generated LLM unit orders after secrets.service")
    (expectEq (llmFixed.config.systemd.services.${llmUnitName}.serviceConfig.Requires or null
    ) null "the generated LLM unit must not place Requires in the [Service] section")
    (expectEq (lib.elem "Requires=secrets.service" (
      iniSectionLines llmUnitText "Unit"
    )) true "the rendered unit declares Requires=secrets.service in its [Unit] section")
    (expectEq (lib.elem "Requires=secrets.service" (
      iniSectionLines llmUnitText "Service"
    )) false "the rendered unit has no Requires=secrets.service left in [Service]")
    (expectEq (lib.elem "Requires=secrets.service" (
      iniSectionLines llmServiceShapeUnitText "Unit"
    )) false "the serviceConfig.Requires shape leaves the [Unit] section without the dependency")
  ];

  # Executable check with systemd's own unit loader: `systemd-analyze verify`
  # (from the same nixpkgs systemd) parses the rendered [Unit] section,
  # composed with a container@ template. A present secrets.service verifies
  # cleanly; an absent one must make verify fail, proving a missing
  # secrets.service cannot silently start the container. The pre-fix
  # `[Service]`-section shape verifies cleanly without the unit — the
  # silent-start defect this contract removes.
  # Dependency directives only. systemd's verify behavior is only reliable
  # on a dependency-only drop-in; the surrounding directives of the full
  # section are covered by the evaluation assertions above.
  unitDependencyLines =
    text:
    let
      depKeys = [
        "After="
        "Wants="
        "Requires="
        "BindsTo="
        "PartOf="
      ];
      isDep = line: lib.any (k: lib.hasPrefix k line) depKeys;
    in
    iniSectionLines text "Unit" |> lib.filter isDep;

  unitDependencyDropin =
    text:
    pkgs.writeText "overrides.conf" (
      "[Unit]\n" + (lib.concatStringsSep "\n" (unitDependencyLines text)) + "\n"
    );

  llmOverrides = unitDependencyDropin llmUnitText;
  llmServiceShapeOverrides = unitDependencyDropin llmServiceShapeUnitText;
  authOverrides = unitDependencyDropin authUnitText;

  # Executable check with systemd's own unit loader: `systemd-analyze --user
  # verify` (from the same nixpkgs systemd) parses the dependency lines of
  # the rendered unit, composed with a container@ template. A present
  # secrets.service verifies cleanly; an absent one must make verify fail,
  # proving a missing secrets.service cannot silently start the container.
  # The pre-fix `[Service]`-section shape verifies cleanly without the unit
  # — the silent-start defect this contract removes. A canary drop-in with
  # a broken ExecStart proves each drop-in is actually loaded.
  # This is not a boot test: nothing starts a VM or a real manager.
  unitDependencyRuntime =
    pkgs.runCommand "surmhosting-unit-dependency-runtime"
      {
        template = pkgs.writeText "container@.service" ''
          [Unit]
          Description=Container '%i'
          DefaultDependencies=no

          [Service]
          Type=oneshot
          ExecStart=${pkgs.coreutils}/bin/true
        '';
        secretsStub = pkgs.writeText "secrets.service" ''
          [Unit]
          Description=secrets stub
          DefaultDependencies=no

          [Service]
          Type=oneshot
          ExecStart=${pkgs.coreutils}/bin/true
        '';
        inherit llmOverrides llmServiceShapeOverrides authOverrides;
      }
      ''
        set -eu
        da="${pkgs.systemd}/bin/systemd-analyze"
        export XDG_RUNTIME_DIR="$PWD/xdg-run"
        mkdir -p "$XDG_RUNTIME_DIR" units 'units/container@lc-llm-proxy.service.d' 'units/container@surm-auth.service.d'

        cp "$template" units/container@.service
        cp "$secretsStub" units/secrets.service
        cp "$llmOverrides" units/container@lc-llm-proxy.service.d/overrides.conf
        cp "$authOverrides" units/container@surm-auth.service.d/overrides.conf

        verifyExpectOk() {
          if ! "$da" --user verify --man=no "$1" >verify-ok.out 2>verify-ok.err; then
            echo "systemd-analyze verify unexpectedly failed for $1" >&2
            cat verify-ok.err >&2
            exit 1
          fi
        }

        verifyExpectMissingSecrets() {
          set +e
          "$da" --user verify --man=no "$1" >verify-missing.out 2>verify-missing.err
          status=$?
          set -e
          if [ "$status" -eq 0 ]; then
            echo "systemd-analyze verify unexpectedly succeeded without secrets.service for $1" >&2
            exit 1
          fi
          if ! grep -q "secrets.service" verify-missing.err; then
            echo "verify output did not mention secrets.service for $1" >&2
            cat verify-missing.err >&2
            exit 1
          fi
        }

        verifyExpectCanary() {
          # A drop-in with a broken ExecStart must fail verification. This
          # proves the drop-in is actually loaded, so the passing and failing
          # cases above are not vacuous. writeText outputs are read-only, so
          # the replacement goes through a temporary file and mv.
          printf '%s\n%s\n%s\n%s\n\n%s\n%s\n' '[Unit]' 'After=secrets.service' 'Wants=secrets.service' 'Requires=secrets.service' '[Service]' 'ExecStart=/nonexistent-canary' > canary-overrides.conf
          mv canary-overrides.conf "$1"
          set +e
          "$da" --user verify --man=no "$2" >canary.out 2>canary.err
          status=$?
          set -e
          if [ "$status" -eq 0 ]; then
            echo "the canary drop-in was not loaded for $2" >&2
            exit 1
          fi
        }

        verifyExpectOk units/container@lc-llm-proxy.service
        verifyExpectOk units/container@surm-auth.service

        mv units/secrets.service units/secrets.service.saved
        verifyExpectMissingSecrets units/container@lc-llm-proxy.service
        verifyExpectMissingSecrets units/container@surm-auth.service

        mv units/secrets.service.saved units/secrets.service
        verifyExpectCanary units/container@lc-llm-proxy.service.d/overrides.conf units/container@lc-llm-proxy.service

        # The [Service]-section shape stays silent when secrets.service is
        # missing, which is exactly the defect the top-level requires option
        # removes.
        mv units/secrets.service units/secrets.service.saved
        rm -f units/container@lc-llm-proxy.service.d/overrides.conf
        cp "$llmServiceShapeOverrides" units/container@lc-llm-proxy.service.d/overrides.conf
        verifyExpectOk units/container@lc-llm-proxy.service

        touch $out
      '';

  internalEntrypoint = checkFixture "internal-entrypoint" (
    let
      customPort = evalHost {
        surmhosting = {
          appsNamespace = "apps.surma.technology";
          internalPort = 8090;
          tls.enable = true;
          dashboard.enable = true;
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.svc-admin = {
                host = "localhost";
                expose.apps.admin = {
                  access.mode = "public";
                  internal.access = "trusted-network";
                  ports = [
                    {
                      port = 8092;
                      hostname = "admin";
                    }
                  ];
                };
              };
            }
          )
        ];
      };
      migratedDashboardOnly = evalHost {
        surmhosting = {
          appsNamespace = "apps.surma.technology";
          tls.enable = true;
          tls.challenge = "dns-01";
          tls.dnsEnvironmentFile = "/var/lib/surmedge-credentials/cloudflare.env";
          dashboard.enable = true;
        };
      };
      legacyHost = evalHost {
        surmhosting = {
          hostname = "surmedge";
          tls.enable = true;
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.legacy.host = "10.0.0.5";
              services.surmhosting.services.legacy.expose.port = 80;
            }
          )
        ];
      };
    in
    [
      (expectEq static.entryPoints.internal.address ":8081"
        "the inventory host exposes the internal entrypoint on the default port"
      )
      (expectEq customPort.config.services.traefik.staticConfigOptions.entryPoints.internal.address
        ":8090"
        "internalPort is honored"
      )
      (expectEq
        migratedDashboardOnly.config.services.traefik.staticConfigOptions.entryPoints.internal.address
        ":8081"
        "a migrated dashboard-only host still gets the internal entrypoint"
      )
      (expectEq
        migratedDashboardOnly.config.services.traefik.dynamicConfigOptions.http.routers.api.entryPoints
        [
          "internal"
        ]
        "a migrated dashboard is restricted to the internal entrypoint"
      )
      (expectEq (
        legacyHost.config.services.traefik.staticConfigOptions.entryPoints ? "internal"
      ) false "a nonmigrated host gets no internal entrypoint")
      (expectEq legacyHost.config.services.traefik.dynamicConfigOptions.http.routers.api { }
        "a nonmigrated host without a dashboard gets no api router content"
      )
    ]
  );

  # internal.enable = false must suppress the app's internal routers while
  # public routing stays independent, and an app that disables internal
  # routing must not keep the shared internal entrypoint alive by itself.
  internalDisabled = checkFixture "internal-disabled" (
    let
      host = evalHost {
        surmhosting = {
          appsNamespace = "apps.surma.technology";
          tls.enable = true;
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.svc-one.expose.apps.app1 = {
                access.mode = "public";
                internal.enable = false;
                ports = [
                  {
                    port = 8080;
                    hostname = "app1";
                  }
                ];
              };
              services.surmhosting.services.svc-two.expose.apps.app2 = {
                access.mode = "public";
                internal.access = "trusted-network";
                ports = [
                  {
                    port = 8081;
                    hostname = "app2";
                  }
                ];
              };
            }
          )
        ];
      };
      allDisabled = evalHost {
        surmhosting = {
          appsNamespace = "apps.surma.technology";
          tls.enable = true;
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.svc-one.expose.apps.app1 = {
                access.mode = "public";
                internal.enable = false;
                ports = [
                  {
                    port = 8080;
                    hostname = "app1";
                  }
                ];
              };
            }
          )
        ];
      };
      http = host.config.services.traefik.dynamicConfigOptions.http;
      allDisabledStatic = allDisabled.config.services.traefik.staticConfigOptions;
    in
    [
      (noSurmhostingAssertions host "internal-disabled")
      (expectEq (http.routers ? "svc-one-app1") false "the disabled app has no internal router")
      (expectEq (
        http.services ? "svc-one-app1"
      ) false "the disabled app has no internal load balancer service")
      (expectEq http.routers."apps-app1-app1".entryPoints [
        "websecure"
      ] "the disabled app keeps its public router on websecure")
      (expectEq http.routers."svc-two-app2".entryPoints [
        "internal"
      ] "the other app keeps its internal router")
      (expectEq (
        host.config.services.traefik.staticConfigOptions.entryPoints ? "internal"
      ) true "the internal entrypoint stays for the app that keeps internal routing")
      (expectEq (
        allDisabledStatic.entryPoints ? "internal"
      ) false "disabling the last internal routing consumer removes the internal entrypoint")
    ]
  );

  # The v1 schema, rendered by the surm-auth module's version = 1 branch.
  # This is the exact configuration shape a pre-rework generation ran; the
  # current v2 binary rejects it.
  v1AuthHost = evalConfig [
    ../surm-auth
    (
      { lib, ... }:
      {
        networking.hostName = "surm-auth-v1-fixture";
        system.stateVersion = "25.05";
        services.surm-auth = {
          enable = true;
          version = 1;
          baseUrl = "https://auth.surma.technology";
          github.clientIdFile = "/var/lib/surm-auth/github-client-id";
          github.clientSecretFile = "/var/lib/surm-auth/github-client-secret";
          session.cookieDomain = ".surma.technology";
          session.cookieName = "_surm_auth";
          session.cookieSecretFile = "/var/lib/surm-auth/cookie-secret";
          apps.hedgedoc = {
            mode = "allowlist";
            seedUsers = [ "surma" ];
          };
        };
      }
    )
  ];

  legacyV1Final = v1AuthHost.config.services.surm-auth.finalConfig;

  # Direct module evaluation must reject the modes removed by the v2
  # two-route contract before it can render a configuration.
  standaloneModeContract = checkFixture "standalone-surm-auth-mode-contract" (
    let
      evalMode =
        mode:
        evalConfig [
          ../surm-auth
          (
            { ... }:
            {
              system.stateVersion = "25.05";
              services.surm-auth = {
                enable = true;
                baseUrl = "https://auth.surma.technology";
                github.clientIdFile = "/var/lib/surm-auth/github-client-id";
                github.clientSecretFile = "/var/lib/surm-auth/github-client-secret";
                session.cookieDomain = ".surma.technology";
                session.cookieSecretFile = "/var/lib/surm-auth/cookie-secret";
                apps.fixture.mode = mode;
              };
            }
          )
        ];
      removedModes = [
        "internal"
        "authenticated"
      ];
    in
    removedModes
    |> lib.map (
      mode:
      expect (
        !(builtins.tryEval (builtins.deepSeq (evalMode mode).config.services.surm-auth.finalConfig true))
        .success
      ) "standalone surm-auth mode `${mode}` must fail module evaluation"
    )
  );

  legacyCompat = checkFixture "legacy-compatibility" (
    let
      # Nonmigrated host with the legacy routing shorthand and no
      # authentication. This shape stays valid: nothing here runs the v1
      # auth runtime.
      legacyRoutingHost = evalHost {
        surmhosting = {
          hostname = "surmedge";
          tls.enable = true;
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.hedgedoc = {
                host = "10.0.0.5";
                expose.port = 80;
                expose.rule = "Host(`hedgedoc.surma.technology`)";
                expose.useTargetHost = true;
              };
            }
          )
        ];
      };
      legacyNoTls = evalHost {
        surmhosting = {
          hostname = "citadel";
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.admin = {
                host = "localhost";
                expose.port = 8092;
              };
            }
          )
        ];
      };
      # Nonmigrated host with a legacy seed list. The repository ships only
      # the v2 surm-auth binary, so this shape must fail evaluation instead
      # of rendering a v1 auth container no binary can run.
      legacyAuthHost = evalHost {
        surmhosting = {
          hostname = "surmedge";
          tls.enable = true;
          auth.domain = "auth.surma.technology";
          auth.github.clientIdFile = "/var/lib/surm-auth/github-client-id";
          auth.github.clientSecretFile = "/var/lib/surm-auth/github-client-secret";
          auth.cookieSecretFile = "/var/lib/surm-auth/cookie-secret";
          auth.cookieDomain = ".surma.technology";
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.services.hedgedoc = {
                host = "10.0.0.5";
                expose.port = 80;
                expose.allowedGitHubUsers = [ "surma" ];
              };
            }
          )
        ];
      };
      # The v1 schema, rendered by the surm-auth module's version = 1 branch.
      # This is the exact configuration shape a pre-rework generation ran;
      # the current v2 binary rejects it (see legacyV1Rejected below).
      legacyV1Final = v1AuthHost.config.services.surm-auth.finalConfig;
      legacyRoutingHttp = legacyRoutingHost.config.services.traefik.dynamicConfigOptions.http;
    in
    [
      (expectEq (
        legacyRoutingHost.config.containers ? "surm-auth"
      ) false "a nonmigrated host without authentication runs no auth container")
      (expectEq legacyRoutingHttp.routers."hedgedoc-hedgedoc".entryPoints [
        "websecure"
      ] "legacy routing shorthand keeps using websecure when TLS is enabled")
      (expectEq legacyRoutingHttp.middlewares."host-rewrite-hedgedoc".headers.customRequestHeaders.Host
        "10.0.0.5"
        "legacy routing shorthand keeps the useTargetHost middleware"
      )
      (expectEq (
        legacyRoutingHost.config.services.traefik.staticConfigOptions.entryPoints ? "internal"
      ) false "the legacy routing host gets no internal entrypoint")
      (expectEq legacyRoutingHost.config.services.traefik.environmentFiles [ ]
        "the legacy routing host gets no environment file"
      )
      (expectEq
        legacyNoTls.config.services.traefik.dynamicConfigOptions.http.routers."admin-admin".entryPoints
        [
          "web"
        ]
        "a TLS-less legacy host keeps routing on the web entrypoint"
      )
      (expectEq (lib.hasAttr "oauth" legacyV1Final) true "the historical v1 schema keeps the oauth key")
      (expectEq legacyV1Final.session.cookie_name "_surm_auth"
        "the historical v1 schema keeps the old cookie name"
      )
      (expectEq legacyV1Final.apps.hedgedoc.allowed_users [
        "surma"
      ] "the historical v1 schema keeps allowed_users")
      (expectMsg legacyAuthHost "rejects the v1 configuration schema"
        "legacy v1 authentication on a nonmigrated host must fail evaluation and name the rollback path"
      )
      (expectEq (lib.any (m: lib.hasInfix "saved generations" m) (
        expectMessages legacyAuthHost
      )) true "the legacy rejection names saved generations as the rollback path")
    ]
  );

  # Executable boundary proof: the current surm-auth v2 binary rejects the
  # v1 configuration schema that a nonmigrated host would render. Running
  # the v1 runtime is therefore only possible from old saved generations,
  # which still contain the v1 binary — not from a newly built generation.
  legacyV1Rejected =
    pkgs.runCommand "surmhosting-legacy-v1-rejected"
      {
        v1ConfigFile = pkgs.writeText "surm-auth-v1-config.yaml" (builtins.toJSON legacyV1Final);
        surmAuthPkg = flakeInputs.self.packages.${pkgs.stdenv.hostPlatform.system}.surm-auth;
      }
      ''
        set +e
        "$surmAuthPkg/bin/surm-auth" --config "$v1ConfigFile" >stdout.log 2>stderr.log
        status=$?
        set -e
        if [ "$status" -eq 0 ]; then
          echo "surm-auth v2 accepted a legacy v1 configuration" >&2
          exit 1
        fi
        if ! grep -q "legacy v1 key 'oauth:'" stderr.log && ! grep -q "legacy v1 key 'oauth:'" stdout.log; then
          echo "the v2 rejection did not cite the legacy oauth key" >&2
          cat stderr.log >&2
          cat stdout.log >&2
          exit 1
        fi
        touch $out
      '';

  nexusConsumerHost = evalConfig [
    ./default.nix
    {
      options.secrets = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (
      { ... }:
      {
        networking.hostName = "surmhosting-consumer-fixture";
        system.stateVersion = "25.05";
        services.surmhosting = lib.mkMerge [
          {
            enable = true;
            hostname = "nexus";
            externalInterface = "eth0";
            internalPort = 8081;
            tls = {
              enable = true;
              challenge = "http-01";
              email = "surma@surma.dev";
            };
          }
          authCommon
        ];
      }
    )
    (repoRoot + "/machines/nexus/service-firefly-importer.nix")
  ];

  nexusBrowserURLs = checkFixture "nexus-browser-urls" (
    let
      importer =
        nexusConsumerHost.config.containers.lc-firefly-im.config.services.firefly-iii-data-importer;
      http = nexusConsumerHost.config.services.traefik.dynamicConfigOptions.http;
    in
    [
      (expectEq importer.settings.VANITY_URL "https://firefly.apps.surma.technology"
        "the importer uses Firefly's derived public browser URL"
      )
      (expectEq importer.settings.FIREFLY_III_URL "http://firefly.nexus.hosts.10.0.0.2.nip.io:8081"
        "the importer keeps its internal Firefly backend URL"
      )
      (expectEq (
        http.routers ? "apps-firefly-imp-firefly-imp"
      ) true "the Firefly importer has a generated public route")
    ]
  );

  authWithoutSeeds = checkFixture "auth-without-legacy-seeds" (
    let
      host = evalHost {
        surmhosting = authCommon // {
          appsNamespace = "apps.surma.technology";
        };
        extraModules = [
          (
            { lib, ... }:
            {
              services.surmhosting.tls.enable = true;
              services.surmhosting.tls.challenge = "dns-01";
              services.surmhosting.tls.dnsEnvironmentFile = "/var/lib/surmedge-credentials/cloudflare.env";
              services.surmhosting.services.svc-app = {
                host = "10.201.0.2";
                expose.apps.myapp = {
                  access.mode = "allowlist";
                  access.seedUsers = [ "surma" ];
                  internal.access = "trusted-network";
                  public.aliases = [ "myapp.surma.technology" ];
                  ports = [
                    {
                      port = 8080;
                      hostname = "app";
                    }
                  ];
                };
              };
            }
          )
        ];
      };
    in
    [
      (expectEq (
        host.config.containers ? "surm-auth"
      ) true "auth.enable keeps the auth container enabled without any legacy allowlist")
      (expectEq (
        host.config.services.traefik.dynamicConfigOptions.http.middlewares ? "auth-myapp"
      ) true "the restricted app gets its auth middleware")
    ]
  );

  invalidDeclarations = checkFixture "invalid-declarations" (
    let
      baseApps = {
        access.mode = "allowlist";
        access.seedUsers = [ "surma" ];
        internal.access = "trusted-network";
        public.aliases = [ ];
        ports = [
          {
            port = 8080;
            hostname = "app";
          }
        ];
      };

      # Host with a migrated namespace, TLS, and auth settings, but no
      # services. Each case supplies its own broken declarations.
      brokenHost =
        surmhosting:
        evalHost {
          surmhosting = lib.recursiveUpdate {
            appsNamespace = "apps.surma.technology";
            tls.enable = true;
            tls.challenge = "dns-01";
            tls.dnsEnvironmentFile = "/var/lib/surmedge-credentials/cloudflare.env";
            auth.domain = "auth.surma.technology";
            auth.github.clientIdFile = "/var/lib/surm-auth-credentials/github-client-id";
            auth.github.clientSecretFile = "/var/lib/surm-auth-credentials/github-client-secret";
            auth.cookieSecretFile = "/var/lib/surm-auth-credentials/cookie-secret";
            auth.cookieDomain = ".surma.technology";
          } surmhosting;
        };

      cases = [
        {
          name = "duplicate-domain";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = baseApps;
            services.svc-two.expose.apps.app2 = lib.recursiveUpdate baseApps {
              public.aliases = [ "app1.apps.surma.technology" ];
            };
          };
          needle = "same public domain is declared by multiple logical apps";
        }
        {
          name = "primary-domain-repeated-as-alias";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              public.aliases = [ "app1.apps.surma.technology" ];
            };
          };
          needle = "repeats its derived primary domain";
        }
        {
          name = "duplicate-alias";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              public.aliases = [
                "one.surma.technology"
                "one.surma.technology"
              ];
            };
          };
          needle = "repeats an alias";
        }
        {
          name = "duplicate-app-key";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = baseApps;
            services.svc-two.expose.apps.app1 = baseApps;
          };
          needle = "duplicate logical app keys";
        }
        {
          name = "seed-users-on-public";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              access.mode = "public";
            };
          };
          needle = "only valid in allowlist mode";
        }
        {
          name = "app-without-ports";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              ports = [ ];
            };
          };
          needle = "declares no ports";
        }
        {
          name = "removed-internal-mode";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              access.mode = "internal";
            };
          };
          needle = null;
        }
        {
          name = "removed-authenticated-mode";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              access.mode = "authenticated";
            };
          };
          needle = null;
        }
        {
          name = "restricted-app-without-auth";
          host = brokenHost {
            services.svc-one.expose.apps.app1 = baseApps;
          };
          needle = "requires authentication";
        }
        {
          name = "legacy-adapter-without-app";
          host = brokenHost {
            services.svc-two.expose.allowedGitHubUsers = [ "surma" ];
            services.svc-two.expose.port = 8080;
          };
          needle = "seeds exactly one allowlist logical app (found 0)";
        }
        {
          name = "legacy-adapter-with-two-allowlist-apps";
          host = brokenHost {
            services.svc-one.expose.allowedGitHubUsers = [ "surma" ];
            services.svc-one.expose.apps.app1 = baseApps;
            services.svc-one.expose.apps.app2 = baseApps;
          };
          needle = "seeds exactly one allowlist logical app (found 2)";
        }
        {
          name = "mixed-legacy-and-app-exposure";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = baseApps;
            services.svc-one.expose.port = 8080;
          };
          needle = "mixes legacy expose.port/expose.ports with expose.apps";
        }
        {
          name = "legacy-exposure-on-migrated-host";
          host = brokenHost {
            services.svc-two.expose.port = 8080;
          };
          needle = "keeps a legacy HTTP exposure on a migrated host";
        }
        {
          name = "cookie-parent-domain-mismatch";
          host = brokenHost {
            auth.enable = true;
            services.svc-one.expose.apps.app1 = lib.recursiveUpdate baseApps {
              public.aliases = [ "app1.other.example" ];
            };
          };
          needle = "does not cover";
        }
        {
          name = "dns01-without-environment-file";
          host = evalHost {
            surmhosting = {
              tls.enable = true;
              tls.challenge = "dns-01";
            };
          };
          needle = "requires tls.dnsEnvironmentFile";
        }
        {
          name = "forwarded-header-trust";
          host = evalHost {
            surmhosting = {
              appsNamespace = "apps.surma.technology";
              tls.enable = true;
              tls.challenge = "dns-01";
              tls.dnsEnvironmentFile = "/var/lib/surmedge-credentials/cloudflare.env";
            };
            extraModules = [
              (
                { lib, ... }:
                {
                  services.traefik.staticConfigOptions.entryPoints.web.forwardedHeaders.trustedIPs = [
                    "100.64.107.114/32"
                  ];
                }
              )
            ];
          };
          needle = "forbids forwarded-header trust";
        }
        {
          name = "missing-apps-namespace";
          host = evalHost {
            surmhosting = {
              tls.enable = true;
            };
            extraModules = [
              (
                { lib, ... }:
                {
                  services.surmhosting.services.svc-one = {
                    host = "10.201.0.2";
                    expose.apps.app1 = {
                      access.mode = "public";
                      internal.access = "trusted-network";
                      ports = [
                        {
                          port = 8080;
                          hostname = "app";
                        }
                      ];
                    };
                  };
                }
              )
            ];
          };
          needle = "requires services.surmhosting.appsNamespace";
        }
      ];

      checkedCases =
        cases
        |> lib.map (
          case:
          if case.needle == null then
            # These cases must make evaluation fail outright (conflicting
            # definitions or a missing access mode). Forcing the assertion
            # VALUES throws before any message is rendered.
            expect (
              !(builtins.tryEval (case.host.config.assertions |> lib.all (a: a.assertion))).success
            ) "fixture case `${case.name}` must fail evaluation"
          else
            expectMsg case.host case.needle "fixture case `${case.name}`"
        );
    in
    checkedCases
  );

  fixtures = {
    inherit
      routers
      authKeys
      http01Migrated
      v2Config
      llmDependency
      unitDependencyRuntime
      internalEntrypoint
      internalDisabled
      legacyCompat
      legacyV1Rejected
      standaloneModeContract
      nexusBrowserURLs
      authWithoutSeeds
      invalidDeclarations
      ;
  };

  all = pkgs.runCommand "surmhosting-focused-tests" { } ''
    ${
      fixtures
      |> lib.attrValues
      |> lib.map (f: "test -e ${f}")
      |> lib.concatStringsSep "\n"
    }
    touch $out
  '';
in
fixtures
// {
  inherit all;
}
