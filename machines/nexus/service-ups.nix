{ config, ... }:
{
  secrets.items.nexus-upsmon-password.target = "/var/lib/nut/upsmon.password";

  systemd.services.upsmon = {
    after = [ "secrets.service" ];
    requires = [ "secrets.service" ];
  };

  power.ups = {
    enable = true;
    mode = "standalone";

    ups.ske = {
      description = "SKE 1500VA/900W UPS";
      driver = "nutdrv_qx";
      port = "auto";

      directives = [
        "vendorid = 0001"
        "productid = 0000"
      ];
    };

    users.upsmon = {
      passwordFile = config.secrets.items.nexus-upsmon-password.target;
      upsmon = "primary";
    };

    upsmon.monitor.ske = {
      user = "upsmon";
    };
  };
}
