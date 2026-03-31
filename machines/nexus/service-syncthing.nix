{ config, pkgs, lib, ... }:
let
  ports = import ./ports.nix;
  shared = import ../../modules/services/syncthing/common.nix { inherit lib pkgs; };
in
{
  secrets.items.nexus-syncthing.target = "/var/lib/syncthing/key.pem";
  secrets.items.syncthing-relay-token = {
    target = "/var/lib/syncthing/relay-token";
    mode = "0400";
  };

  services.syncthing.enable = true;
  services.syncthing.openDefaultPorts = true;
  services.syncthing.user = "surma";
  services.syncthing.dataDir = "/dump/state/syncthing/data";
  services.syncthing.configDir = "/dump/state/syncthing/config";
  services.syncthing.databaseDir = "/dump/state/syncthing/db";
  services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
  services.syncthing.key = config.secrets.items.nexus-syncthing.target;
  services.syncthing.settings.folders."audiobooks".path = "/dump/audiobooks";
  services.syncthing.settings.folders."audiobooks".devices = [ "arbiter" ];
  services.syncthing.settings.folders."scratch".path = "/dump/scratch";
  services.syncthing.settings.folders."scratch".devices = [
    "dragoon"
    "shopisurm"
  ];
  services.syncthing.settings.folders."ebooks".path = "/dump/ebooks";
  services.syncthing.settings.folders."ebooks".devices = [
    "dragoon"
    "arbiter"
    "shopisurm"
  ];
  services.syncthing.settings.folders."surmvault".path = "/dump/surmvault";
  services.syncthing.settings.folders."surmvault".devices = [
    "dragoon"
    "arbiter"
    "shopisurm"
  ];
  services.syncthing.settings.devices.dragoon = shared.devices.dragoon;
  services.syncthing.settings.devices.archon = shared.devices.archon;
  services.syncthing.settings.devices.arbiter = shared.devices.arbiter;
  services.syncthing.settings.devices.shopisurm = shared.devices.shopisurm;
  services.syncthing.guiAddress = "0.0.0.0:${toString ports.syncthingGui}";

  services.surmhosting.services.syncthing.expose.port = ports.syncthingGui;

  systemd.services.syncthing-init.serviceConfig.ExecStartPre = let
    waitForApi = pkgs.writeShellScript "wait-for-syncthing-api" ''
      set -euo pipefail

      api_key="$(${pkgs.libxml2}/bin/xmllint --xpath 'string(/configuration/gui/apikey)' ${lib.escapeShellArg "${config.services.syncthing.configDir}/config.xml"} 2>/dev/null)"
      [ -n "$api_key" ]

      for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
        response="$(${pkgs.curl}/bin/curl -fsSk -H "X-API-Key: $api_key" http://127.0.0.1:${toString ports.syncthingGui}/rest/config/options 2>/dev/null || true)"
        if [ -n "$response" ] && printf '%s' "$response" | ${pkgs.jq}/bin/jq -e . >/dev/null 2>&1; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      exit 1
    '';
  in
  [ "${waitForApi}" ];

  systemd.services.syncthing-private-relay = {
    description = "Inject private Syncthing relay URL";
    after = [
      "syncthing.service"
      "syncthing-init.service"
      "secrets.service"
    ];
    wants = [
      "syncthing.service"
      "syncthing-init.service"
      "secrets.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        injectRelay = shared.mkPrivateRelayScript {
          tokenFile = config.secrets.items.syncthing-relay-token.target;
          configXml = "${config.services.syncthing.configDir}/config.xml";
          apiUrl = "http://127.0.0.1:${toString ports.syncthingGui}";
          curlExtraArgs = "--retry 60 --retry-delay 1 --retry-all-errors";
        };
      in
      "${injectRelay}";
    };
  };
}
