{ pkgs, lib, ... }:
let
  ips = import ../../ips.nix;
  reconciler = pkgs.callPackage ../../packages/tailscale-cf-dns { };

  zone = "surma.technology";
  suffix = "vpn.${zone}";

  # Ownership marker written into every record comment. The reconciler
  # creates, updates, and deletes only records carrying this exact string,
  # so anything hand-made under the suffix survives untouched.
  comment = "managed-by:tailscale-cf-dns";

  # The Cloudflare token provisioned by service-scout.nix. Declaring
  # secrets.items.scout-cloudflare-api-token a second time would create a
  # competing target for one secret, so this file reads the existing path
  # instead of writing its own copy.
  apiTokenFile = "/var/lib/scout/cloudflare-api-token";

  # Every host in the registry that has a tailnet address. `tailscale6` is
  # optional: a host without one gets an A record and no AAAA record.
  vpnHosts = lib.mapAttrs (_: host: {
    v4 = host.tailscale;
    v6 = host.tailscale6 or "";
  }) (lib.filterAttrs (_: host: host ? tailscale) ips.hosts);

  # Rendered config, and also the restart trigger: editing a tailnet
  # address in ips.nix changes this file, which re-arms the timer.
  configJSON = pkgs.writeText "tailscale-cf-dns.json" (
    builtins.toJSON {
      inherit zone suffix comment;
      ttl = 300;
      hosts = vpnHosts;
    }
  );
in
{
  # Publishes <host>.vpn.surma.technology for every tailnet host in
  # ips.nix. The registry is the source of truth: adding a machine is a
  # commit, not a background discovery. The reconciler logs drift against
  # the live tailnet but never acts on it.
  systemd.services.tailscale-cf-dns = {
    description = "Converge Cloudflare DNS records for tailnet hosts";
    wants = [
      "network-online.target"
      "secrets.service"
    ];
    after = [
      "network-online.target"
      "secrets.service"
      "tailscaled.service"
    ];
    environment.CLOUDFLARE_API_TOKEN_FILE = apiTokenFile;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${reconciler}/bin/tailscale-cf-dns ${configJSON}";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    unitConfig = {
      # Finite retry budget: transient Cloudflare or network failures retry,
      # a persistent problem lands the unit in a failed state instead of
      # hammering the API.
      StartLimitIntervalSec = "30min";
      StartLimitBurst = 5;
    };
  };

  systemd.timers.tailscale-cf-dns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Delayed after boot so tailscaled and the secrets service are up, then
      # daily. Tailnet addresses are stable for the life of a node, so this
      # timer exists to repair manual edits in Cloudflare, not to track churn.
      OnActiveSec = "3min";
      OnUnitActiveSec = "1d";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
    # A tailnet address edit in ips.nix changes the rendered config, which
    # restarts the timer and re-arms the delayed run.
    restartTriggers = [ configJSON ];
  };
}
