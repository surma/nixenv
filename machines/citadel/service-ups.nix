{ config, ... }:
{
  secrets.items.citadel-upsmon-password.target = "/var/lib/nut/upsmon.password";

  systemd.services.upsmon = {
    after = [ "secrets.service" ];
    requires = [ "secrets.service" ];
  };

  # Secondary NUT client: Citadel's upsmon watches the Eaton 5SC on Nexus
  # and shuts Citadel down when Nexus reports the critical battery state.
  power.ups = {
    enable = true;
    mode = "netclient";

    upsmon.monitor.ske = {
      system = "ske@10.0.0.2";
      user = "citadel-upsmon";
      passwordFile = config.secrets.items.citadel-upsmon-password.target;
      type = "secondary";
    };
  };
}
