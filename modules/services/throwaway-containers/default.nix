{
  config,
  lib,
  pkgs,
  ...
}:
# Throwaway NixOS containers: an HTTP API that makes short-lived
# nixos-container boxes from a NixOS config. Rules: every box has a TTL
# (extend as often as you like), a minutely timer reaps expired ones, boot
# wipes them all, each runs on an ephemeral root, no ports are published (a
# private veth per box, outbound via NAT), no auth (VPN only). Only
# containers named tc-* are touched. Spec: Sausage site
# research/nixos-containers-api.
let
  cfg = config.services.throwaway-containers;

  # Same directory names as nixos/modules/virtualisation/nixos-containers.nix.
  prefix = lib.optionalString (lib.versionAtLeast config.system.stateVersion "22.05") "nixos-";

  bin = lib.getExe cfg.package;
  args = lib.escapeShellArgs [
    "--state-dir"
    "/var/lib/throwaway-containers"
    "--conf-dir"
    "/etc/${prefix}containers"
    "--root-dir"
    "/var/lib/${prefix}containers"
    # nixos configs build against the host's own nixpkgs, so most paths are
    # already in the store.
    "--nixpkgs"
    "${pkgs.path}"
  ];

  # nixos-container, nix, systemctl, chattr come from the host system.
  common = {
    path = [ "/run/current-system/sw" ];
    environment = {
      HOME = "/root";
      NIX_PATH = "nixpkgs=${pkgs.path}";
    };
  };
in
{
  options.services.throwaway-containers = {
    enable = lib.mkEnableOption "the throwaway NixOS containers HTTP API";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8093;
      description = "Port of the HTTP API (all interfaces).";
    };

    defaultTtl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = "TTL in seconds when a create request has none.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The throwaway-containers package.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.enableContainers = true;

    # Outbound internet for the boxes (nixos-container's default pool).
    # Merges with other NAT users (surmhosting sets the external interface).
    networking.nat = {
      enable = true;
      internalIPs = [ "10.233.0.0/16" ];
    };

    # Boot wipes every throwaway box: nothing comes back after a reboot.
    # Not restarted on deploys (that would kill the running boxes).
    systemd.services.throwaway-containers-wipe = common // {
      description = "Destroy throwaway containers left from before boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "throwaway-containers.service" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${bin} wipe ${args}";
      };
    };

    systemd.services.throwaway-containers = common // {
      description = "Throwaway NixOS containers HTTP API";
      wantedBy = [ "multi-user.target" ];
      wants = [ "throwaway-containers-wipe.service" ];
      after = [
        "network.target"
        "throwaway-containers-wipe.service"
      ];
      serviceConfig = {
        # Runs as root: nixos-container needs it.
        ExecStart = "${bin} serve ${args} --port ${toString cfg.port} --default-ttl ${toString cfg.defaultTtl}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # The host reaps, not the caller: also while the API is down.
    systemd.services.throwaway-containers-reap = common // {
      description = "Destroy expired throwaway containers";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bin} reap ${args}";
      };
    };

    systemd.timers.throwaway-containers-reap = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
        AccuracySec = "5s";
      };
    };
  };
}
