{ ... }:
let
  port = 3128;
in
{
  services.tinyproxy = {
    enable = true;
    settings = {
      Port = port;
      Listen = "0.0.0.0";
      Allow = [
        "127.0.0.1"
        "100.64.0.0/10"
      ];
      Timeout = 600;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
