# Evaluation check for modules/services/nexus-apps (flake check
# `nexus-apps`): a minimal surmhosting host with sample apps, plus a host
# without apps. It proves generated configuration values, not runtime
# behaviour.
{
  pkgs,
  lib ? pkgs.lib,
  surmhosting,
}:
let
  evalHost =
    apps:
    import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        surmhosting.nixosModules.default
        ./default.nix
        {
          networking.hostName = "nexus-apps-check";
          system.stateVersion = "26.05";
          services.surmhosting = {
            enable = true;
            hostname = "nexus";
            externalInterface = "eth0";
            # Like nexus (users.users.surma.uid is unset): no host uid needed.
            containeruser.uid = null;
          } // lib.optionalAttrs (apps ? brain-serve) {
            appsNamespace = "apps.surma.technology";
            tls = {
              enable = true;
              challenge = "http-01";
              email = "surma@surma.dev";
            };
            auth = {
              enable = true;
              stateHostPath = "/var/lib/surm-auth-state";
              unitDependencies = {
                requires = [ "secrets.service" ];
                after = [ "secrets.service" ];
              };
              domain = "auth.surma.technology";
              aliases = [ "auth.apps.surma.technology" ];
              cookieDomain = ".surma.technology";
              github.clientIdFile = "/var/lib/surm-auth-credentials/github-client-id";
              github.clientSecretFile = "/var/lib/surm-auth-credentials/github-client-secret";
              cookieSecretFile = "/var/lib/surm-auth-credentials/cookie-secret";
              bootstrapAdmins = [
                {
                  provider = "github";
                  id = "234957";
                }
              ];
            };
          };
          nexus.apps = apps;
          nexus.appsForges.gitea = {
            api = "http://gitea.example:8081/api/v1";
            tokenFile = "/var/lib/nixos-admin/forge/gitea-token";
          };
        }
        {
          # Host/container settings that nexus.apps does not own. These are
          # intentionally composed with the generated app container. The
          # backend freeform values are shallow-merged, so restate app-state.
          config = lib.mkIf (apps ? brain-serve) {
            services.surmhosting.services.brain-serve = {
              backend."nixos-container" = {
                service = {
                  wants = [ "secrets.service" ];
                  after = [ "secrets.service" ];
                  serviceConfig.MemoryMax = "8G";
                };
                allowedDevices = [
                  { modifier = "rw"; node = "/dev/dri/renderD128"; }
                  { modifier = "rw"; node = "/dev/dri/card1"; }
                ];
                bindMounts = {
                  app-state = {
                    mountPoint = "/var/lib/app";
                    hostPath = "/dump/state/brain-serve";
                    isReadOnly = false;
                  };
                  dri = {
                    mountPoint = "/dev/dri";
                    hostPath = "/dev/dri";
                    isReadOnly = false;
                  };
                  llm-key = {
                    mountPoint = "/var/lib/credentials";
                    hostPath = "/var/lib/scout";
                    isReadOnly = true;
                  };
                };
              };
            };
          };
        }
      ];
    };

  host = evalHost {
    sample = {
      flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/sample.git";
      env = {
        PORT = "8080";
        DATABASE_PASSWORD_FILE = "/run/app-secrets/db-password";
      };
      secrets.db-password = "/var/lib/postgres-sample/password";
      requires = [ "postgres-sample-setup.service" ];
      after = [ "postgres-sample-setup.service" ];
      expose.apps.sample = {
        access.mode = "public";
        internal.access = "trusted-network";
        public.enable = false;
        ports = [
          {
            port = 8080;
            hostname = "sample";
          }
        ];
      };
      containerConfig = {
        environment.etc."sample-extra".text = "extra";
      };
    };
    pinned = {
      flake = "git+ssh://git@github.com/surma/pinned-app";
      ref = "dev";
      rev = "0123456789abcdef0123456789abcdef01234567";
      deployOn = "ci";
      program = "pinned-server";
      stateDir = "/srv/pinned";
      healthUrl = "http://pinned.nexus.hosts:8081/health";
    };
    brain-serve = {
      flake = "git+ssh://git@github.com/surma/brain";
      program = "brain";
      forge = "github";
      repo = "surma/brain";
      stateDir = "/dump/state/brain-serve";
      expose = {
        apps.brain = {
          access.mode = "allowlist";
          access.seedUsers = [ "surma" ];
          internal.access = "trusted-network";
          public.aliases = [ "brain.surma.technology" ];
          ports = [ { port = 8080; hostname = "brain-serve"; } ];
        };
        apps.public-brain = {
          access.mode = "public";
          internal.access = "trusted-network";
          public.aliases = [ "public-brain.surma.technology" ];
          ports = [ { port = 8081; hostname = "public-brain"; } ];
        };
      };
      containerConfig = { lib, ... }: {
        systemd.services.app = {
          wantedBy = lib.mkForce [ ];
          environment.PATH = lib.mkForce
            "/nix/var/nix/profiles/app/bin:${lib.makeBinPath [ pkgs.git pkgs.openssh ]}:/run/current-system/sw/bin";
          serviceConfig.ExecStart = lib.mkForce "/nix/var/nix/profiles/app/bin/brain serve --port 8080";
        };
        systemd.timers.app.wantedBy = [ "timers.target" ];
      };
    };
  };

  emptyHost = evalHost { };

  c = host.config;
  sample = c.containers.lc-sample;
  sampleApp = sample.config.systemd.services.app;
  pinnedApp = c.containers.lc-pinned.config.systemd.services.app;
  brainService = c.services.surmhosting.services.brain-serve;
  brainBackend = brainService.backend."nixos-container";
  brainContainer = c.containers.lc-brain-serv;
  brainApp = brainContainer.config.systemd.services.app;
  registry = c.nexus.appsRegistry;

  failedAssertions = h: map (a: a.message) (lib.filter (a: !a.assertion) h.config.assertions);
  ownAssertions =
    h: lib.filter (m: lib.hasInfix "nexus.apps" m || lib.hasInfix "surmhosting" m) (failedAssertions h);

  expectEq = actual: expected: msg: {
    ok = actual == expected;
    msg = "${msg}: expected ${lib.generators.toPretty { } expected}, got ${
      lib.generators.toPretty { } actual
    }";
  };
  expect = ok: msg: { inherit ok msg; };

  conditions = [
    (expectEq (ownAssertions host) [ ] "no failed nexus.apps/surmhosting assertions")
    (expectEq (ownAssertions emptyHost) [ ] "no failed assertions without apps")

    # surmhosting service + container
    (expect (c.services.surmhosting.services ? sample) "surmhosting service `sample` exists")
    (expect (c.services.surmhosting.services ? brain-serve) "surmhosting service `brain-serve` exists")
    (expectEq sample.ephemeral true "container stays ephemeral")
    (expectEq brainContainer.bindMounts.app-state {
      mountPoint = "/var/lib/app";
      hostPath = "/dump/state/brain-serve";
      isReadOnly = false;
    } "Brain state bind mount preserves the existing host directory")
    (expectEq brainBackend.bindMounts.llm-key {
      mountPoint = "/var/lib/credentials";
      hostPath = "/var/lib/scout";
      isReadOnly = true;
    } "Brain LLM key mount stays read-only")
    (expectEq brainBackend.allowedDevices [
      { modifier = "rw"; node = "/dev/dri/renderD128"; }
      { modifier = "rw"; node = "/dev/dri/card1"; }
    ] "Brain iGPU device nodes are passed to the container")
    (expectEq brainBackend.bindMounts.dri {
      mountPoint = "/dev/dri";
      hostPath = "/dev/dri";
      isReadOnly = false;
    } "Brain iGPU device directory is mounted")
    (expectEq brainBackend.service.serviceConfig.MemoryMax "8G" "Brain container keeps its 8G memory cap")
    (expect (lib.elem "secrets.service" brainBackend.service.wants) "Brain container waits for the secrets service")
    (expect (lib.elem "secrets.service" brainBackend.service.after) "Brain container starts after the secrets service")
    (expectEq brainService.expose.apps.brain.access.mode "allowlist" "Brain private API remains allowlisted")
    (expectEq brainService.expose.apps.brain.public.aliases [ "brain.surma.technology" ] "Brain private alias stays")
    (expectEq (map (p: { inherit (p) hostname port; }) brainService.expose.apps.brain.ports) [
      { port = 8080; hostname = "brain-serve"; }
    ] "Brain private API stays on the existing host")
    (expectEq brainService.expose.apps.public-brain.access.mode "public" "Brain public server stays public")
    (expectEq brainService.expose.apps.public-brain.public.aliases [ "public-brain.surma.technology" ] "Brain public alias stays")
    (expectEq (map (p: { inherit (p) hostname port; }) brainService.expose.apps.public-brain.ports) [
      { port = 8081; hostname = "public-brain"; }
    ] "Brain public API stays on the existing host")
    (expectEq sample.bindMounts.app-state {
      mountPoint = "/var/lib/app";
      hostPath = "/var/lib/apps/sample";
      isReadOnly = false;
    } "state folder bind mount (default stateDir)")
    (expectEq c.containers.lc-pinned.bindMounts.app-state.hostPath "/srv/pinned" "custom stateDir")
    (expectEq sample.bindMounts.app-secret-db-password {
      mountPoint = "/run/app-secrets/db-password";
      hostPath = "/var/lib/postgres-sample/password";
      isReadOnly = true;
    } "secret bind mount")
    (expect (lib.elem "postgres-sample-setup.service"
      c.systemd.services."container@lc-sample".after
    ) "container unit after the postgres setup")
    (expect (lib.elem "postgres-sample-setup.service"
      c.systemd.services."container@lc-sample".requires
    ) "container unit requires the postgres setup")
    (expect (
      c.services.traefik.dynamicConfigOptions.http.routers ? sample-sample
    ) "expose passed through (internal router sample-sample)")
    (expectEq sample.config.environment.etc."sample-extra".text "extra" "containerConfig is imported")

    # app.service in the container
    (expectEq sampleApp.serviceConfig.ExecStart "/nix/var/nix/profiles/app/bin/sample" "ExecStart from the profile")
    (expectEq pinnedApp.serviceConfig.ExecStart "/nix/var/nix/profiles/app/bin/pinned-server" "custom program")
    (expectEq sampleApp.unitConfig.ConditionPathExists "/nix/var/nix/profiles/app/bin/sample" "skip while not deployed")
    (expectEq sampleApp.serviceConfig.User "containeruser" "runs as containeruser")
    (expectEq sampleApp.serviceConfig.Restart "always" "Restart=always")
    (expectEq sampleApp.environment.STATE_DIR "/var/lib/app" "STATE_DIR")
    (expectEq sampleApp.environment.PORT "8080" "env passed through")
    (expect (lib.elem "multi-user.target" sampleApp.wantedBy) "app.service starts at boot")
    (expectEq brainApp.serviceConfig.ExecStart "/nix/var/nix/profiles/app/bin/brain serve --port 8080"
      "Brain private app.service uses the per-app profile")
    (expectEq brainApp.wantedBy [ ] "Brain private service starts from its delayed timer")
    (expectEq brainApp.environment.PATH "/nix/var/nix/profiles/app/bin:${lib.makeBinPath [ pkgs.git pkgs.openssh ]}:/run/current-system/sw/bin"
      "Brain API sync can locate the active app binary, Git, and SSH")
    (expect (lib.elem "timers.target" brainContainer.config.systemd.timers.app.wantedBy)
      "Brain delayed-start timer is enabled")

    # state folder: created on the host, owned by the container user from inside
    (expect (lib.elem "d /var/lib/apps/sample - - - - -" c.systemd.tmpfiles.rules) "state folder created on the host")
    (expect (lib.elem "d /var/lib/app 0750 ${c.services.surmhosting.containeruser.name} users - -"
      sample.config.systemd.tmpfiles.rules
    ) "container hands the state folder to its user")

    # registry
    (expectEq registry.sample {
      name = "sample";
      flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/sample.git";
      ref = "main";
      rev = null;
      deployOn = "push";
      package = "default";
      program = "sample";
      forge = "gitea";
      repo = "surma/sample";
      stateDir = "/var/lib/apps/sample";
      healthUrl = null;
      container = "lc-sample";
      unit = "app.service";
      profile = "/nix/var/nix/profiles/per-container/lc-sample/app";
    } "registry entry with defaults")
    (expectEq registry.brain-serve {
      name = "brain-serve";
      flake = "git+ssh://git@github.com/surma/brain";
      ref = "main";
      rev = null;
      deployOn = "push";
      package = "default";
      program = "brain";
      forge = "github";
      repo = "surma/brain";
      stateDir = "/dump/state/brain-serve";
      healthUrl = null;
      container = "lc-brain-serv";
      unit = "app.service";
      profile = "/nix/var/nix/profiles/per-container/lc-brain-serv/app";
    } "Brain registry entry and GitHub app source")
    (expectEq {
      inherit (registry.pinned)
        forge
        repo
        ref
        rev
        deployOn
        program
        healthUrl
        ;
    } {
      forge = "github";
      repo = "surma/pinned-app";
      ref = "dev";
      rev = "0123456789abcdef0123456789abcdef01234567";
      deployOn = "ci";
      program = "pinned-server";
      healthUrl = "http://pinned.nexus.hosts:8081/health";
    } "registry entry with overrides")
    (expectEq c.environment.etc."nexus/apps.json".source c.nexus.appsRegistryFile "registry in /etc/nexus/apps.json")

    # nixos-admin registry (format: nixos-admin-web README, "Registry")
    (expectEq c.nexus.appsAdminConfig {
      apps = [
        {
          name = "brain-serve";
          container = "lc-brain-serv";
          flake = "git+ssh://git@github.com/surma/brain";
          ref = "main";
          rev = "";
          deploy_on = "push";
          package = "default";
          forge = "github";
          forge_repo = "surma/brain";
          service = "app.service";
          profile = "/nix/var/nix/profiles/per-container/lc-brain-serv/app";
        }
        {
          name = "pinned";
          container = "lc-pinned";
          flake = "git+ssh://git@github.com/surma/pinned-app";
          ref = "dev";
          rev = "0123456789abcdef0123456789abcdef01234567";
          deploy_on = "ci";
          package = "default";
          forge = "github";
          forge_repo = "surma/pinned-app";
          service = "app.service";
          profile = "/nix/var/nix/profiles/per-container/lc-pinned/app";
          health_url = "http://pinned.nexus.hosts:8081/health";
        }
        {
          name = "sample";
          container = "lc-sample";
          flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/sample.git";
          ref = "main";
          rev = "";
          deploy_on = "push";
          package = "default";
          forge = "gitea";
          forge_repo = "surma/sample";
          forge_api = "http://gitea.example:8081/api/v1";
          forge_token_file = "/var/lib/nixos-admin/forge/gitea-token";
          service = "app.service";
          profile = "/nix/var/nix/profiles/per-container/lc-sample/app";
        }
      ];
    } "nixos-admin registry (forge settings only where configured)")
    (expectEq emptyHost.config.nexus.appsAdminConfig { apps = [ ]; } "empty nixos-admin registry without apps")

    # without apps the module defines nothing
    (expect (!(emptyHost.config.environment.etc ? "nexus/apps.json")) "no registry file without apps")
    (expectEq emptyHost.config.services.surmhosting.services { } "no services without apps")
    (expectEq emptyHost.config.containers { } "no containers without apps")
  ];

  failures = lib.filter (x: !x.ok) conditions;
in
lib.throwIfNot (failures == [ ])
  "nexus-apps check failed:\n${lib.concatMapStringsSep "\n" (x: "  - ${x.msg}") failures}"
  (
    pkgs.runCommand "nexus-apps-check" { } ''
      mkdir $out
      cp ${c.nexus.appsRegistryFile} $out/nexus-apps.json
      cp ${c.nexus.appsAdminConfigFile} $out/nixos-admin-apps.json
    ''
  )
