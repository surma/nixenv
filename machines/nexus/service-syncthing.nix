{ config, pkgs, ... }:
let
  ports = import ./ports.nix;
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
  services.syncthing.settings.devices.dragoon.id =
    "TAYU7SA-CCAFI4R-ZLB6FNM-OCPMW5W-6KEYYPI-ANW52FK-DUHVT7Z-L2GYBAB";
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
        injectRelay = pkgs.writeShellScript "syncthing-private-relay" ''
          set -euo pipefail

          token_file="${config.secrets.items.syncthing-relay-token.target}"
          config_xml="${config.services.syncthing.configDir}/config.xml"
          relay_prefix="relay://relay.sync.surma.technology:22067/"
          api_url="http://127.0.0.1:${toString ports.syncthingGui}"

          [ -s "$token_file" ]
          [ -f "$config_xml" ]

          api_key="$(${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' "$config_xml")"
          relay_token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"
          relay_url="$relay_prefix?token=$relay_token"

          api_curl() {
            ${pkgs.curl}/bin/curl -fsSk \
              --retry 60 \
              --retry-delay 1 \
              --retry-all-errors \
              -H "X-API-Key: $api_key" \
              "$@"
          }

          current_options="$(api_curl "$api_url/rest/config/options")"
          updated_options="$(
            printf '%s' "$current_options" | ${pkgs.jq}/bin/jq --arg relay "$relay_url" --arg prefix "$relay_prefix" '
              .listenAddresses = (
                [ $relay ]
                + ((.listenAddresses // []) | map(select(startswith($prefix) | not)))
                | unique
              )
            '
          )"

          printf '%s' "$updated_options" \
            | api_curl -X PUT -d @- "$api_url/rest/config/options" >/dev/null

          restart_required="$(api_curl "$api_url/rest/config/restart-required" | ${pkgs.jq}/bin/jq -r '.requiresRestart')"
          if [ "$restart_required" = "true" ]; then
            api_curl -X POST "$api_url/rest/system/restart" >/dev/null
          fi
        '';
      in
      "${injectRelay}";
    };
  };
}
