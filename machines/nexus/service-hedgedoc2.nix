{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  package = inputs.self.packages.${system}.hedgedoc2;
  baseUrl = "https://hedgedoc.surma.technology";
  stateDirectory = "/var/lib/hedgedoc2";
  sessionSecretFile = "${stateDirectory}/session-secret";
  githubSecretDirectory = "/var/lib/hedgedoc2-secrets";
  githubEnvironmentFile = "${githubSecretDirectory}/github.env";

  backendStart = pkgs.writeShellScript "hedgedoc2-backend-start" ''
    set -euo pipefail
    umask 077

    if [ ! -e "${sessionSecretFile}" ]; then
      temporarySecret="$(${pkgs.coreutils}/bin/mktemp "${sessionSecretFile}.tmp.XXXXXX")"
      trap '${pkgs.coreutils}/bin/rm -f "$temporarySecret"' EXIT
      ${pkgs.openssl}/bin/openssl rand -hex 32 > "$temporarySecret"
      ${pkgs.coreutils}/bin/mv "$temporarySecret" "${sessionSecretFile}"
      trap - EXIT
    fi

    if [ ! -s "${sessionSecretFile}" ]; then
      echo "The HedgeDoc 2 session secret is empty" >&2
      exit 1
    fi

    HD_AUTH_SESSION_SECRET="$(${pkgs.coreutils}/bin/cat "${sessionSecretFile}")"
    export HD_AUTH_SESSION_SECRET
    exec ${package}/bin/hedgedoc2-backend
  '';
in
{
  # HedgeDoc 1 used CMD_* names for this encrypted GitHub credential.
  secrets.items.hedgedoc-github-env.command = ''
    set -euo pipefail

    ${pkgs.coreutils}/bin/install -d -m 0750 -o surma -g users "${githubSecretDirectory}"
    temporaryFile="$(${pkgs.coreutils}/bin/mktemp "${githubEnvironmentFile}.tmp.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temporaryFile"' EXIT

    ${pkgs.gnused}/bin/sed \
      -e 's/^CMD_GITHUB_CLIENTID=/HD_AUTH_OIDC_GITHUB_CLIENT_ID=/' \
      -e 's/^CMD_GITHUB_CLIENTSECRET=/HD_AUTH_OIDC_GITHUB_CLIENT_SECRET=/' \
      > "$temporaryFile"

    if ! ${pkgs.gnugrep}/bin/grep -q '^HD_AUTH_OIDC_GITHUB_CLIENT_ID=' "$temporaryFile"; then
      ${pkgs.coreutils}/bin/printf '%s\n' 'The HedgeDoc GitHub client ID is missing' >&2
      exit 1
    fi

    if ! ${pkgs.gnugrep}/bin/grep -q '^HD_AUTH_OIDC_GITHUB_CLIENT_SECRET=' "$temporaryFile"; then
      ${pkgs.coreutils}/bin/printf '%s\n' 'The HedgeDoc GitHub client secret is missing' >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/chown surma:users "$temporaryFile"
    ${pkgs.coreutils}/bin/chmod 0440 "$temporaryFile"
    ${pkgs.coreutils}/bin/mv "$temporaryFile" "${githubEnvironmentFile}"
    trap - EXIT
  '';

  systemd.tmpfiles.rules = [
    "d /dump/state/hedgedoc2 0750 surma users - -"
  ];

  services.surmhosting.services.hedgedoc2 = {
    containerService = {
      wants = [ "secrets.service" ];
      after = [ "secrets.service" ];
    };

    expose.ports = [
      {
        port = 3000;
        hostname = "backend";
        rule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`) && (PathPrefix(`/realtime`) || PathPrefix(`/api`) || PathPrefix(`/public`) || PathPrefix(`/media`) || PathPrefix(`/uploads`) || PathPrefix(`/apidoc`))'';
      }
      {
        port = 3001;
        hostname = "frontend";
        rule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`)'';
      }
    ];

    container = {
      bindMounts = {
        state = {
          mountPoint = stateDirectory;
          hostPath = "/dump/state/hedgedoc2";
          isReadOnly = false;
        };
        github-secret = {
          mountPoint = githubSecretDirectory;
          hostPath = githubSecretDirectory;
          isReadOnly = true;
        };
      };

      config = {
        system.stateVersion = "25.05";

        systemd.tmpfiles.rules = [
          "d ${stateDirectory} 0750 containeruser users - -"
          "d ${stateDirectory}/uploads 0750 containeruser users - -"
        ];

        systemd.services.hedgedoc2-backend = {
          description = "HedgeDoc 2 backend";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          environment = {
            HD_BASE_URL = baseUrl;
            HD_RENDERER_BASE_URL = baseUrl;
            HD_BACKEND_PORT = "3000";
            HD_BACKEND_BIND_IP = "0.0.0.0";
            HD_DATABASE_TYPE = "sqlite";
            HD_DATABASE_NAME = "${stateDirectory}/hedgedoc.sqlite";
            HD_AUTH_LOCAL_ENABLE_LOGIN = "true";
            HD_AUTH_LOCAL_ENABLE_REGISTER = "true";
            HD_AUTH_LOCAL_MINIMAL_PASSWORD_STRENGTH = "2";
            HD_AUTH_OIDC_SERVERS = "github";
            HD_AUTH_OIDC_GITHUB_PROVIDER_NAME = "GitHub";
            HD_AUTH_OIDC_GITHUB_ISSUER = "https://github.com";
            HD_AUTH_OIDC_GITHUB_THEME = "github";
            HD_AUTH_OIDC_GITHUB_AUTHORIZE_URL = "https://github.com/login/oauth/authorize";
            HD_AUTH_OIDC_GITHUB_TOKEN_URL = "https://github.com/login/oauth/access_token";
            HD_AUTH_OIDC_GITHUB_USERINFO_URL = "https://api.github.com/user";
            HD_AUTH_OIDC_GITHUB_SCOPE = "read:user user:email";
            HD_AUTH_OIDC_GITHUB_USER_ID_FIELD = "id";
            HD_AUTH_OIDC_GITHUB_USER_NAME_FIELD = "login";
            HD_AUTH_OIDC_GITHUB_DISPLAY_NAME_FIELD = "name";
            HD_AUTH_OIDC_GITHUB_PROFILE_PICTURE_FIELD = "avatar_url";
            HD_AUTH_OIDC_GITHUB_EMAIL_FIELD = "email";
            HD_AUTH_OIDC_GITHUB_ENABLE_REGISTRATION = "true";
            HD_MEDIA_BACKEND_TYPE = "filesystem";
            HD_MEDIA_BACKEND_FILESYSTEM_UPLOAD_PATH = "${stateDirectory}/uploads";
            HD_NOTE_PERMISSIONS_MAX_GUEST_LEVEL = "write";
            HD_NOTE_PERMISSIONS_DEFAULT_EVERYONE = "write";
            HD_NOTE_PERMISSIONS_DEFAULT_LOGGED_IN = "write";
            HD_LOG_LEVEL = "info";
            HD_LOG_SHOW_TIMESTAMP = "true";
          };
          serviceConfig = {
            ExecStart = backendStart;
            EnvironmentFile = [ githubEnvironmentFile ];
            User = "containeruser";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        systemd.services.hedgedoc2-frontend = {
          description = "HedgeDoc 2 frontend";
          wantedBy = [ "multi-user.target" ];
          wants = [ "hedgedoc2-backend.service" ];
          after = [ "hedgedoc2-backend.service" ];
          environment = {
            HOSTNAME = "0.0.0.0";
            PORT = "3001";
            HD_BASE_URL = baseUrl;
            HD_RENDERER_BASE_URL = baseUrl;
            HD_INTERNAL_API_URL = "http://127.0.0.1:3000";
          };
          serviceConfig = {
            ExecStart = "${package}/bin/hedgedoc2-frontend";
            User = "containeruser";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
  };

  services.traefik.dynamicConfigOptions.http.routers = {
    hedgedoc2-backend.priority = 100;
    hedgedoc2-frontend.priority = 1;
  };
}
