{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.services.nixos-deploy;
in
{
  options.services.nixos-deploy = {
    enable = mkEnableOption "nixos-deploy web UI for triggering nixos-rebuild";

    package = mkOption {
      type = types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nixos-deploy;
      description = "The nixos-deploy package to use.";
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
      default = "/var/lib/nixos-deploy";
      description = "Directory to store deploy logs and metadata.";
    };

    webhookURL = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional webhook URL to POST deploy status notifications to.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nixos-deploy = {
      description = "NixOS Deploy — web UI for nixos-rebuild";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        NIXOS_DEPLOY_LISTEN = cfg.listenAddress;
        NIXOS_DEPLOY_FLAKE_URL = cfg.flakeURL;
        NIXOS_DEPLOY_STATE_DIR = cfg.stateDir;
        # Point HOME at the state dir so nix cache writes go there
        # instead of /root (which is read-only due to ProtectHome).
        HOME = cfg.stateDir;
      } // (lib.optionalAttrs (cfg.webhookURL != null) {
        NIXOS_DEPLOY_WEBHOOK_URL = cfg.webhookURL;
      });

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/nixos-deploy";
        Restart = "always";
        RestartSec = "5s";
        StateDirectory = "nixos-deploy";

        # Runs as root because nixos-rebuild requires it.
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
