{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.services.surm-auth;

  # Runtime credential paths injected through systemd's LoadCredential.
  # The rendered configuration must reference these paths, never the
  # root-only bind-mount sources (auth-rework section 6.3).
  credentialDir = "/run/credentials/surm-auth.service";

  accessModes = [
    "internal"
    "public"
    "authenticated"
    "allowlist"
  ];

  # The complete v2 configuration contract consumed by the Go app
  # (auth-rework section 5.1). It contains file paths only, never
  # decrypted secret material, so rendering it into the store is safe.
  v2Config = {
    version = 2;
    server = {
      address = cfg.listenAddress;
      base_url = cfg.baseUrl;
      auth_domains = cfg.authDomains;
    };
    session = {
      cookie_name = cfg.session.cookieName;
      cookie_domain = cfg.session.cookieDomain;
      cookie_secret_file = "${credentialDir}/cookie-secret";
      cookie_secure = cfg.session.cookieSecure;
      duration = cfg.session.duration;
    };
    policy.file = cfg.policy.file;
    audit.file = cfg.audit.file;
    providers.github = {
      client_id_file = "${credentialDir}/github-client-id";
      client_secret_file = "${credentialDir}/github-client-secret";
    };
    bootstrap_admins = cfg.bootstrapAdmins;
    apps = mapAttrs (_: app: {
      mode = app.mode;
      domains = app.domains;
      seed_users = app.seedUsers;
    }) cfg.apps;
  };

  # The v1 schema, kept only for nonmigrated host generations that still
  # run the v1 binary (auth-rework section 2). Version 2 rejects this
  # shape with a migration error.
  v1Config = {
    server = {
      address = cfg.listenAddress;
      base_url = cfg.baseUrl;
    };
    oauth = {
      github = {
        client_id_file = cfg.github.clientIdFile;
        client_secret_file = cfg.github.clientSecretFile;
      };
    };
    session = {
      cookie_name = cfg.session.cookieName;
      cookie_domain = cfg.session.cookieDomain;
      cookie_secret_file = cfg.session.cookieSecretFile;
      cookie_secure = cfg.session.cookieSecure;
      duration = cfg.session.duration;
    };
    apps = mapAttrs (_: app: {
      allowed_users = app.seedUsers;
    }) cfg.apps;
  };

  renderedConfig = if cfg.version == 2 then v2Config else v1Config;

  configFile = pkgs.writeText "surm-auth-config.yaml" (builtins.toJSON renderedConfig);
in
{
  options.services.surm-auth = {
    enable = mkEnableOption "surm-auth authentication service";

    version = mkOption {
      type = types.enum [
        1
        2
      ];
      default = 2;
      description = ''
        Configuration contract version. Version 2 renders the v2 contract
        from auth-rework section 5.1. Version 1 renders the legacy schema
        for host generations that still run the v1 binary.
      '';
    };

    package = mkOption {
      type = types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.surm-auth;
      description = "The surm-auth package to use";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Address to listen on";
    };

    baseUrl = mkOption {
      type = types.str;
      description = "Canonical HTTPS base URL for the auth service";
      example = "https://auth.surma.technology";
    };

    authDomains = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Hosts the login and callback validator accepts for the auth
        service itself. The first entry should match the canonical
        base URL host. Aliases enable the additional auth hosts.
      '';
      example = [
        "auth.surma.technology"
        "auth.apps.surma.technology"
      ];
    };

    github = {
      clientIdFile = mkOption {
        type = types.path;
        description = ''
          Source path for the GitHub OAuth client ID credential. For
          version 2 this is the LoadCredential source; the rendered
          configuration always reads the credential copy.
        '';
      };

      clientSecretFile = mkOption {
        type = types.path;
        description = ''
          Source path for the GitHub OAuth client secret credential. For
          version 2 this is the LoadCredential source; the rendered
          configuration always reads the credential copy.
        '';
      };
    };

    session = {
      cookieName = mkOption {
        type = types.str;
        default = "_surm_auth2";
        description = "Name of the session cookie";
      };

      cookieDomain = mkOption {
        type = types.str;
        description = "Domain for the session cookie";
        example = ".surma.technology";
      };

      cookieSecretFile = mkOption {
        type = types.path;
        description = ''
          Source path for the cookie signing secret credential. For
          version 2 this is the LoadCredential source; the rendered
          configuration always reads the credential copy.
        '';
      };

      cookieSecure = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to set the Secure flag on cookies (HTTPS only)";
      };

      duration = mkOption {
        type = types.str;
        default = "168h";
        description = "Session duration (e.g., 168h = 7 days)";
      };
    };

    policy.file = mkOption {
      type = types.str;
      default = "/var/lib/surm-auth/policy.json";
      description = "Path to the persistent policy file";
    };

    audit.file = mkOption {
      type = types.str;
      default = "/var/lib/surm-auth/audit.log";
      description = "Path to the audit log file";
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
      description = "Nix-owned administrator identities reasserted at startup";
    };

    finalConfig = mkOption {
      type = types.anything;
      readOnly = true;
      description = ''
        The rendered configuration attribute set. The generated YAML file is
        its JSON serialization. It contains file paths only, never decrypted
        secret material.
      '';
    };

    apps = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            mode = mkOption {
              type = types.enum accessModes;
              description = ''
                Access mode for this app: `internal`, `public`,
                `authenticated`, or `allowlist`.
              '';
            };
            domains = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Domains this app is reachable on (primary domain first)";
            };
            seedUsers = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Usernames resolved into initial grants on first start (allowlist mode only)";
            };
          };
        }
      );
      default = { };
      description = "Per-app access policy keys";
    };
  };

  config = mkIf cfg.enable {
    services.surm-auth.finalConfig = renderedConfig;

    systemd.services.surm-auth = {
      description = "Surm Auth Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/surm-auth --config ${configFile}";
        Restart = "always";
        RestartSec = "5s";

        # Security hardening
        DynamicUser = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      }
      // (optionalAttrs (cfg.version == 2) {
        # Separate credentials from writable policy state: the state
        # directory persists the policy and audit files while
        # LoadCredential hands over the decrypted secrets
        # (auth-rework sections 6.2 and 6.3).
        StateDirectory = "surm-auth";
        StateDirectoryMode = "0700";
        LoadCredential = [
          "github-client-id:${cfg.github.clientIdFile}"
          "github-client-secret:${cfg.github.clientSecretFile}"
          "cookie-secret:${cfg.session.cookieSecretFile}"
        ];
      });
    };
  };
}
