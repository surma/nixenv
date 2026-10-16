# Evaluation check for modules/services/nexus-apps (flake check
# `nexus-apps`): a minimal surmhosting host with two sample apps, plus a host
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
            containeruser.uid = 1000;
          };
          nexus.apps = apps;
          nexus.appsForges.gitea = {
            api = "http://gitea.example:8081/api/v1";
            tokenFile = "/var/lib/nixos-admin/forge/gitea-token";
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
      deployOn = "push";
      program = "pinned-server";
      stateDir = "/srv/pinned";
      healthUrl = "http://pinned.nexus.hosts:8081/health";
    };
  };

  emptyHost = evalHost { };

  c = host.config;
  sample = c.containers.lc-sample;
  sampleApp = sample.config.systemd.services.app;
  pinnedApp = c.containers.lc-pinned.config.systemd.services.app;
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
    (expectEq sample.ephemeral true "container stays ephemeral")
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

    # host state folder
    (expect (lib.elem "d /var/lib/apps/sample 0750 1000 users - -" c.systemd.tmpfiles.rules) "state folder created on the host")

    # registry
    (expectEq registry.sample {
      name = "sample";
      flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/sample.git";
      ref = "main";
      rev = null;
      deployOn = "ci";
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
      deployOn = "push";
      program = "pinned-server";
      healthUrl = "http://pinned.nexus.hosts:8081/health";
    } "registry entry with overrides")
    (expectEq c.environment.etc."nexus/apps.json".source c.nexus.appsRegistryFile "registry in /etc/nexus/apps.json")

    # nixos-admin registry (format: nixos-admin-web README, "Registry")
    (expectEq c.nexus.appsAdminConfig {
      apps = [
        {
          name = "pinned";
          container = "lc-pinned";
          flake = "git+ssh://git@github.com/surma/pinned-app";
          ref = "dev";
          rev = "0123456789abcdef0123456789abcdef01234567";
          deploy_on = "push";
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
          deploy_on = "ci";
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
