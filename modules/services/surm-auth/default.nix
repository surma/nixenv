{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.surm-auth;

  # Generate YAML config from Nix options
  configFile = pkgs.writeText "surm-auth-config.yaml" (
    builtins.toJSON {
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
      apps = cfg.apps;
    }
  );
in
{
  options.services.surm-auth = {
    enable = mkEnableOption "surm-auth authentication service";

    package = mkOption {
      type = types.package;
      default = pkgs.surm-auth;
      description = "The surm-auth package to use";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Address to listen on";
    };

    baseUrl = mkOption {
      type = types.str;
      description = "Base URL for the auth service";
      example = "https://auth.surma.technology";
    };

    github = {
      clientIdFile = mkOption {
        type = types.path;
        description = "Path to file containing GitHub OAuth Client ID";
      };

      clientSecretFile = mkOption {
        type = types.path;
        description = "Path to file containing GitHub OAuth Client Secret";
      };
    };

    session = {
      cookieName = mkOption {
        type = types.str;
        default = "_surm_auth";
        description = "Name of the session cookie";
      };

      cookieDomain = mkOption {
        type = types.str;
        description = "Domain for the session cookie";
        example = ".surma.technology";
      };

      cookieSecretFile = mkOption {
        type = types.path;
        description = "Path to file containing cookie encryption secret";
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

    apps = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            allowed_users = mkOption {
              type = types.listOf types.str;
              description = "List of GitHub usernames allowed to access this app";
              example = [
                "surma"
                "stimhub"
              ];
            };
          };
        }
      );
      default = { };
      description = "Per-app user allowlists";
    };
  };

  config = mkIf cfg.enable {
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
      };
    };
  };
}
