{ ... }:
let
  ports = import ./ports.nix;
in
{
  networking.firewall.allowedTCPPorts = [ ports.mqtt ];

  services.mosquitto.enable = true;
  services.mosquitto.listeners = [
    {
      users.ha.hashedPassword = "$7$101$7KOip01uJDP71vA0$y9vhvHE/pxka3/eQiP+Fs4EVjaXCJ4gwChMtFxiCH/jTDricu5MW3BjMx3XTyo2vXAVgUd/QHKuwoejw8h1OuQ==";
      users.ha.acl = [
        "readwrite #"
      ];
    }
  ];
  services.mosquitto.dataDir = "/dump/state/mosquitto";
  services.mosquitto.persistence = false;
}
