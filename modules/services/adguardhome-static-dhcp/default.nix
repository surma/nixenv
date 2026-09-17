{
  config,
  lib,
  pkgs,
  ...
}:
let
  reconciler = pkgs.callPackage ./adguardhome-reconciler { };

  # The option rendered to static JSON: consumed by the reconciler binary
  # and wired into the timer as a restart trigger (retrigger on registry
  # change).
  staticDHCPJSON = pkgs.writeText "adguardhome-static-dhcp.json" (
    builtins.toJSON config.services.adguardhome.staticDHCP
  );
in
{
  # Static DHCP reservations, keyed by MAC address. This AdGuardHome
  # version (0.107.78) keeps all leases in data/leases.json and ignores
  # yaml lease keys, so the option is rendered to JSON and converged into
  # the REST API by the adguardhome-reconcile-leases timer (see below).
  options.services.adguardhome.staticDHCP = lib.mkOption {
    description = "Static DHCP reservations keyed by MAC address";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Reserved IPv4 address";
          };
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "DHCP hostname of the lease";
          };
        };
      }
    );
    default = { };
  };

  # Runtime machinery only when AdGuardHome runs and leases are declared.
  config =
    lib.mkIf (config.services.adguardhome.enable && config.services.adguardhome.staticDHCP != { })
      {
        # Static lease reconciliation (see the staticDHCP option above).
        # Trigger model: the delayed timer fires it (2 min after every timer
        # (re)start, i.e. at boot and whenever a registry edit changes the JSON
        # restart trigger below); Restart=on-failure retries temporary failures
        # without blocking nixos-rebuild switch, and the start limit stops
        # unbounded retry loops.
        systemd.services.adguardhome-reconcile-leases = {
          after = [ "adguardhome.service" ];
          environment.ADGUARD_URL = "http://127.0.0.1:${toString config.services.adguardhome.port}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${reconciler}/bin/adguardhome-reconciler ${staticDHCPJSON}";
            Restart = "on-failure";
            RestartSec = "5s";
          };
          unitConfig = {
            # Finite retry budget: 5 failures within 10 min put the unit in a
            # failed state instead of retrying forever.
            StartLimitIntervalSec = "10min";
            StartLimitBurst = 5;
          };
        };

        systemd.timers.adguardhome-reconcile-leases = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # Delayed, not at boot: AdGuardHome is up by then; a timer restart
            # (registry change below) re-arms this delay.
            OnActiveSec = "2min";
          };
          # Standard restart trigger: the timer restarts on switch whenever the
          # registry output changes, which re-arms the delayed run.
          restartTriggers = [ staticDHCPJSON ];
        };
      };
}
