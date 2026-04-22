{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.services.nexus-admin;
in
{
  options.services.nexus-admin = {
    enable = mkEnableOption "Nexus Admin — web UI for NixOS deploys, journal logs, and unit management";

    package = mkOption {
      type = types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nexus-admin;
      description = "The nexus-admin package to use.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1:8092";
      description = "Address and port for the HTTP server to listen on.";
    };

    flakeURL = mkOption {
      type = types.str;
      description = "Default flake URL for nixos-rebuild (e.g., github:surma/nixenv#nexus).";
      example = "github:surma/nixenv#nexus";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/nexus-admin";
      description = "Directory to store deploy logs and metadata.";
    };

    webhookURL = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional webhook URL to POST deploy status notifications to.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nexus-admin = {
      description = "Nexus Admin — web UI for NixOS deploys and journal logs";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        NEXUS_ADMIN_LISTEN = cfg.listenAddress;
        NEXUS_ADMIN_FLAKE_URL = cfg.flakeURL;
        NEXUS_ADMIN_STATE_DIR = cfg.stateDir;
        # Point HOME at the state dir so nix cache writes go there
        # instead of /root (which is read-only due to ProtectHome).
        HOME = cfg.stateDir;
      } // (lib.optionalAttrs (cfg.webhookURL != null) {
        NEXUS_ADMIN_WEBHOOK_URL = cfg.webhookURL;
      });

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/nexus-admin";
        Restart = "always";
        RestartSec = "5s";
        StateDirectory = "nexus-admin";

        # Runs as root because nixos-rebuild and journalctl -M require it.
        # Hardened where possible despite root.
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = false; # nixos-rebuild needs privilege
      };

      path = [
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.git
        pkgs.coreutils
        pkgs.systemd
      ];
    };
  };
}
