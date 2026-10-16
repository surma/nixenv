# nexus.apps.<name>: one app = one surmhosting NixOS container whose
# `app.service` runs whatever the app's own Nix profile points at.
#
# nixenv only allocates the box (container, state folder, secrets, env,
# routing). The code comes from the app's own flake: nixos-admin builds it
# on the host, flips the per-app profile and restarts `app.service`
# (site research/app-containers-nix-run.md). This module therefore never
# references the app flake itself; it only writes a registry entry that
# tells nixos-admin what to build and where to put it.
#
# Paths:
# - Profile: host /nix/var/nix/profiles/per-container/<container>/app is the
#   container's /nix/var/nix/profiles/app (nixos-containers bind-mounts the
#   per-container profiles dir). Nix's GC scans /nix/var/nix/profiles
#   recursively, so every generation link there is a GC root.
# - State: host `stateDir` (default /var/lib/apps/<name>) is bound read-write
#   to /var/lib/app and exported as STATE_DIR. surmhosting containers are
#   ephemeral, so this is the only place that survives a restart.
# - Secrets: each `secrets.<key>` host file is bound read-only to
#   /run/app-secrets/<key>.
# - Registry: /etc/nexus/apps.json (also `config.nexus.appsRegistryFile`).
#   nixos-admin reads the same apps in its own format from
#   `config.nexus.appsAdminConfigFile` (machines/nexus/service-nexus-admin.nix).
#
# With `nexus.apps = { }` (the default) the module defines nothing.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.nexus.apps;
  containerUser = config.services.surmhosting.containeruser;

  inContainerProfile = "/nix/var/nix/profiles/app";
  stateMount = "/var/lib/app";
  secretsDir = "/run/app-secrets";

  # Forge and `owner/repo` from the flake URL, for matching webhooks.
  # Handles `github:owner/repo` and `<scheme>://[user@]host[:port]/owner/repo[.git]`.
  parseForge =
    url:
    let
      github = builtins.match "github:([^/]+)/([^/?]+)" url;
      generic = builtins.match "[a-z+]+://([^/@]+@)?([^/:]+)(:[0-9]+)?/([^/]+)/([^/?]+)" url;
      stripGit = lib.removeSuffix ".git";
    in
    if github != null then
      {
        forge = "github";
        repo = "${lib.elemAt github 0}/${stripGit (lib.elemAt github 1)}";
      }
    else if generic != null then
      {
        forge = if lib.elemAt generic 1 == "github.com" then "github" else "gitea";
        repo = "${lib.elemAt generic 3}/${stripGit (lib.elemAt generic 4)}";
      }
    else
      {
        forge = null;
        repo = null;
      };

  appModule =
    { name, config, ... }:
    let
      parsed = parseForge config.flake;
    in
    {
      options = {
        flake = mkOption {
          type = types.str;
          example = "git+ssh://containeruser@gitea.surma.technology:2222/surma/supply-depot.git";
          description = ''
            Flake URL of the app, without `?ref=`/`?rev=`: the deploy job
            builds `<flake>?ref=<ref>&rev=<sha>#packages.<system>.<package>`.
          '';
        };
        ref = mkOption {
          type = types.str;
          default = "main";
          description = "Tracked branch.";
        };
        rev = mkOption {
          type = types.nullOr (types.strMatching "[0-9a-f]{40}");
          default = null;
          description = "Pins the app to this commit; the branch head is ignored while set.";
        };
        deployOn = mkOption {
          type = types.enum [
            "push"
            "ci"
          ];
          default = "push";
          description = ''
            Deploy gate. `push` (default): every push to `ref` deploys the
            branch head right away; merges to `main` are already gated by
            CI. `ci`: optional opt-in; only commits on `ref` whose CI passed
            deploy (nixos-admin asks the forge, see `nexus.appsForges`).
          '';
        };
        package = mkOption {
          type = types.str;
          default = "default";
          description = "Package attribute of the app flake (`packages.<system>.<package>`).";
        };
        program = mkOption {
          type = types.str;
          default = name;
          description = "Binary that `app.service` runs: `bin/<program>` of the built package.";
        };
        containerName = mkOption {
          type = types.str;
          default = "lc-${lib.substring 0 10 name}";
          defaultText = lib.literalExpression ''"lc-''${lib.substring 0 10 name}"'';
          description = "NixOS container name (surmhosting's default naming).";
        };
        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/apps/${name}";
          description = "Host folder bound read-write to ${stateMount} (STATE_DIR) in the container.";
        };
        env = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Environment of `app.service`. STATE_DIR is always set.";
        };
        secrets = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = {
            db-password = "/var/lib/postgres-supply-depot/password";
          };
          description = "Host files bound read-only to ${secretsDir}/<key> in the container.";
        };
        wants = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Host units the container unit wants.";
        };
        requires = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Host units the container unit requires.";
        };
        after = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Host units the container unit starts after.";
        };
        expose = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Passed unchanged to `services.surmhosting.services.<name>.expose`.";
        };
        containerConfig = mkOption {
          type = types.deferredModule;
          default = { };
          description = "Extra NixOS module for the container (users, extra services, ...).";
        };
        healthUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "http://supply-depot.nexus.hosts.10.0.0.2.nip.io:8081/";
          description = "Optional URL the deploy job checks after a restart (registry only).";
        };
        forge = mkOption {
          type = types.nullOr (
            types.enum [
              "gitea"
              "github"
            ]
          );
          default = parsed.forge;
          defaultText = "derived from `flake`";
          description = "Forge that sends this app's webhooks.";
        };
        repo = mkOption {
          type = types.nullOr types.str;
          default = parsed.repo;
          defaultText = "derived from `flake`";
          description = "`owner/repo` on the forge (webhook `repository.full_name`).";
        };
      };
    };

  hostProfile = app: "/nix/var/nix/profiles/per-container/${app.containerName}/app";
  programPath = app: "${inContainerProfile}/bin/${app.program}";

  containerModule =
    name: app:
    { lib, ... }:
    {
      system.stateVersion = lib.mkDefault "26.05";

      systemd.services.app = {
        description = "App ${name} (runs ${inContainerProfile})";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        # An empty profile means "not deployed yet": skip, don't crash-loop.
        unitConfig.ConditionPathExists = programPath app;
        environment = app.env // {
          STATE_DIR = stateMount;
        };
        serviceConfig = {
          ExecStart = programPath app;
          User = containerUser.name;
          WorkingDirectory = stateMount;
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };

  surmhostingService = name: app: {
    backend."nixos-container" = {
      name = app.containerName;
      service = {
        inherit (app) wants requires after;
      };
      bindMounts = {
        app-state = {
          mountPoint = stateMount;
          hostPath = app.stateDir;
          isReadOnly = false;
        };
      }
      // lib.mapAttrs' (
        key: hostPath:
        lib.nameValuePair "app-secret-${key}" {
          mountPoint = "${secretsDir}/${key}";
          inherit hostPath;
          isReadOnly = true;
        }
      ) app.secrets;
      config = {
        imports = [
          app.containerConfig
          (containerModule name app)
        ];
      };
    };
    inherit (app) expose;
  };

  registryEntry = name: app: {
    inherit name;
    inherit (app)
      flake
      ref
      rev
      deployOn
      package
      program
      forge
      repo
      stateDir
      healthUrl
      ;
    container = app.containerName;
    unit = "app.service";
    profile = hostProfile app;
  };

  registry = lib.mapAttrs registryEntry cfg;
  registryFile = pkgs.writeText "nexus-apps.json" (builtins.toJSON registry);

  # The same apps in nixos-admin's registry format (nixos-admin-web README,
  # "App deploys" > "Registry"): `{ apps = [ ... ]; }` with snake_case keys.
  # Forge API base and token come from `nexus.appsForges.<forge>`; without
  # an entry nixos-admin derives the API from the flake URL.
  adminEntry =
    name: app:
    let
      forgeCfg =
        if app.forge != null && config.nexus.appsForges ? ${app.forge} then
          config.nexus.appsForges.${app.forge}
        else
          {
            api = null;
            tokenFile = null;
          };
    in
    {
      inherit name;
      inherit (app) flake ref package;
      container = app.containerName;
      rev = if app.rev == null then "" else app.rev;
      deploy_on = app.deployOn;
      forge = app.forge;
      forge_repo = app.repo;
      service = "app.service";
      profile = hostProfile app;
    }
    // lib.optionalAttrs (forgeCfg.api != null) { forge_api = forgeCfg.api; }
    // lib.optionalAttrs (forgeCfg.tokenFile != null) { forge_token_file = forgeCfg.tokenFile; }
    // lib.optionalAttrs (app.healthUrl != null) { health_url = app.healthUrl; };

  adminConfig = {
    apps = lib.mapAttrsToList adminEntry cfg;
  };
  adminConfigFile = pkgs.writeText "nixos-admin-apps.json" (builtins.toJSON adminConfig);

  appAssertions =
    name: app:
    let
      at = "nexus.apps.${name}";
    in
    [
      {
        assertion = !(lib.hasInfix "?" app.flake);
        message = "${at}.flake must not contain a query (`?ref=`/`?rev=`); use `ref` and `rev`.";
      }
      {
        assertion = app.forge != null && app.repo != null;
        message = "${at}: cannot derive `forge`/`repo` from flake `${app.flake}`; set them explicitly.";
      }
      {
        assertion = builtins.match "[A-Za-z0-9._+-]+" app.program != null;
        message = "${at}.program must be a plain binary name, got `${app.program}`.";
      }
      {
        assertion = lib.all (key: builtins.match "[A-Za-z0-9._-]+" key != null) (lib.attrNames app.secrets);
        message = "${at}.secrets keys must be plain file names.";
      }
      {
        assertion = lib.hasPrefix "/" app.stateDir;
        message = "${at}.stateDir must be an absolute host path.";
      }
    ];
in
{
  options.nexus = {
    apps = mkOption {
      type = types.attrsOf (types.submodule appModule);
      default = { };
      description = ''
        Apps that run in their own surmhosting container from a per-app Nix
        profile that nixos-admin builds and flips.
      '';
    };

    appsRegistry = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      default = registry;
      description = "Registry entries of `nexus.apps` for nixos-admin (also /etc/nexus/apps.json).";
    };

    appsRegistryFile = mkOption {
      type = types.path;
      readOnly = true;
      default = registryFile;
      defaultText = "JSON file of `nexus.appsRegistry`";
      description = "Store path of the registry JSON.";
    };

    appsForges = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            api = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "http://gitea.nexus.hosts.10.0.0.2.nip.io:8081/api/v1";
              description = "API base URL (Gitea: ending in `/api/v1`). Null: nixos-admin derives it from the flake URL.";
            };
            tokenFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Host file with an API token, needed for private repos.";
            };
          };
        }
      );
      default = { };
      description = ''
        How nixos-admin reaches each forge (`gitea`, `github`) for the
        optional CI gate (`deployOn = "ci"`): API base URL and token file,
        applied to every app on that forge.
      '';
    };

    appsAdminConfig = mkOption {
      type = types.anything;
      readOnly = true;
      default = adminConfig;
      description = "`nexus.apps` in nixos-admin's registry format (`services.nixos-admin.appsConfigFile`).";
    };

    appsAdminConfigFile = mkOption {
      type = types.path;
      readOnly = true;
      default = adminConfigFile;
      defaultText = "JSON file of `nexus.appsAdminConfig`";
      description = "Store path of `nexus.appsAdminConfig` as JSON; also written with no apps (`{\"apps\":[]}`).";
    };
  };

  config = lib.mkIf (cfg != { }) {
    assertions = [
      {
        assertion = containerUser.uid != null;
        message = "nexus.apps needs services.surmhosting.containeruser.uid to own the state folders.";
      }
    ]
    ++ lib.concatLists (lib.mapAttrsToList appAssertions cfg);

    services.surmhosting.services = lib.mapAttrs surmhostingService cfg;

    systemd.tmpfiles.rules = lib.mapAttrsToList (
      _: app: "d ${app.stateDir} 0750 ${toString containerUser.uid} users - -"
    ) cfg;

    environment.etc."nexus/apps.json".source = registryFile;
  };
}
