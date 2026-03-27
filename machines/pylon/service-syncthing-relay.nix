{ config, pkgs, ... }:
let
  ports = import ./ports.nix;
in
{
  secrets.items.syncthing-relay-token = {
    target = "/var/lib/syncthing-relay/token";
    mode = "0400";
  };

  networking.firewall.allowedTCPPorts = [ ports.syncthingRelay ];

  systemd.services.syncthing-relay = {
    description = "Private Syncthing relay";
    after = [
      "network-online.target"
      "secrets.service"
    ];
    wants = [
      "network-online.target"
      "secrets.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "syncthing-relay";
      LoadCredential = [ "relay-token:${config.secrets.items.syncthing-relay-token.target}" ];
      ExecStart = let
        relayStart = pkgs.writeShellScript "syncthing-relay-start" ''
          set -euo pipefail

          token_file="$CREDENTIALS_DIRECTORY/relay-token"
          token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"

          exec ${pkgs.syncthing-relay}/bin/strelaysrv \
            --keys=/var/lib/syncthing-relay \
            --listen=:${toString ports.syncthingRelay} \
            --status-srv= \
            --provided-by=surma \
            --pools= \
            --ext-address=relay.sync.surma.technology:${toString ports.syncthingRelay} \
            --token="$token"
        '';
      in
      "${relayStart}";
      Restart = "on-failure";
    };
  };
}
