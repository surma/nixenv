{ config, ... }:
let
  ports = import ./ports.nix;
in
{
  secrets.items.nexus-upsmon-password.target = "/var/lib/nut/upsmon.password";
  secrets.items.citadel-upsmon-password.target = "/var/lib/nut/upsmon-citadel.password";

  systemd.services.upsmon = {
    after = [ "secrets.service" ];
    requires = [ "secrets.service" ];
  };

  # Citadel's secondary upsmon connects to upsd from its established
  # LAN address. Scoped to that exact source; never in allowedTCPPorts.
  networking.firewall.extraInputRules = ''
    ip saddr 10.0.0.32 tcp dport ${toString ports.nut} accept comment "NUT upsd for citadel"
  '';

  power.ups = {
    enable = true;
    mode = "standalone";

    upsd.listen = [
      { address = "0.0.0.0"; }
    ];

    ups.ske = {
      description = "Eaton 5SC";
      driver = "usbhid-ups";
      port = "auto";
    };

    users = {
      upsmon = {
        passwordFile = config.secrets.items.nexus-upsmon-password.target;
        upsmon = "primary";
      };
      citadel-upsmon = {
        passwordFile = config.secrets.items.citadel-upsmon-password.target;
        upsmon = "secondary";
      };
    };

    upsmon.monitor.ske = {
      user = "upsmon";
    };
  };
}
