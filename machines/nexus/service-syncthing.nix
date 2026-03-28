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
  services.syncthing.settings.folders."audiobooks".devices = [
    "dragoon"
    "arbiter"
  ];
  services.syncthing.settings.folders."scratch".path = "/dump/scratch";
  services.syncthing.settings.folders."scratch".devices = [ "dragoon" ];
  services.syncthing.settings.folders."ebooks".path = "/dump/ebooks";
  services.syncthing.settings.folders."ebooks".devices = [
    "dragoon"
    "arbiter"
  ];
  services.syncthing.settings.folders."surmvault".path = "/dump/surmvault";
  services.syncthing.settings.folders."surmvault".devices = [ "dragoon" ];
  services.syncthing.settings.devices.dragoon = shared.devices.dragoon;
  services.syncthing.settings.devices.archon = shared.devices.archon;
  services.syncthing.settings.devices.arbiter.id =
    "7HXMC4G-66H3UDT-BRJ6ATT-3HOXUVN-XIMDBOT-JSFEOO3-HRR3NVF-P4GFUQN";
  services.syncthing.guiAddress = "0.0.0.0:${toString ports.syncthingGui}";

  services.surmhosting.services.syncthing.expose.port = ports.syncthingGui;

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
