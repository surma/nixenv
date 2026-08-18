{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  package = inputs.self.packages.${system}.hedgedoc2;
  baseUrl = "http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io";
  containerAddress = "10.201.250.2";
  stateDirectory = "/var/lib/hedgedoc2";
  sessionSecretFile = "${stateDirectory}/session-secret";

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
  systemd.tmpfiles.rules = [
    "d /dump/state/hedgedoc2 0750 surma users - -"
  ];

  # Use a fixed high container address. Adding this service must not renumber
  # the existing containers that surmhosting allocates sequentially.
  containers.hedgedoc2 = {
    autoStart = true;
    privateNetwork = true;
    localAddress = containerAddress;
    hostAddress = "10.201.250.1";
    ephemeral = true;
    nixpkgs = pkgs.path;

    bindMounts.state = {
      mountPoint = stateDirectory;
      hostPath = "/dump/state/hedgedoc2";
      isReadOnly = false;
    };

    config = {
      system.stateVersion = "25.05";

      users.users.containeruser = {
        uid = config.users.users.surma.uid;
        isNormalUser = true;
      };

      networking.firewall.enable = false;
      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = [ "8.8.8.8" ];

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

  systemd.services."container@hedgedoc2" = {
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = {
      MemoryMax = "4G";
      MemorySwapMax = "0";
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      hedgedoc2-backend = {
        rule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`) && (PathPrefix(`/realtime`) || PathPrefix(`/api`) || PathPrefix(`/public`) || PathPrefix(`/media`) || PathPrefix(`/uploads`) || PathPrefix(`/apidoc`))'';
        service = "hedgedoc2-backend";
        entryPoints = [ "web" ];
        priority = 100;
      };
      hedgedoc2-frontend = {
        rule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`)'';
        service = "hedgedoc2-frontend";
        entryPoints = [ "web" ];
        priority = 1;
      };
    };

    services = {
      hedgedoc2-backend.loadBalancer.servers = [
        { url = "http://${containerAddress}:3000"; }
      ];
      hedgedoc2-frontend.loadBalancer.servers = [
        { url = "http://${containerAddress}:3001"; }
      ];
    };
  };
}
