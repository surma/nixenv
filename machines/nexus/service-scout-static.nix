{ pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d /dump/state/scout-static 0755 surma users - -"
  ];

  services.surmhosting.services.scout-static = {
    expose.ports = [
      {
        port = 8080;
        hostname = "scout-static";
      }
    ];
    container = {
      config = {
        system.stateVersion = "25.05";

        systemd.services.scout-static = {
          description = "Scout static file server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.simple-http-server}/bin/simple-http-server -i -p 8080 /var/lib/scout-static";
            User = "containeruser";
            Restart = "always";
            RestartSec = 5;
          };
        };
      };

      bindMounts.state = {
        mountPoint = "/var/lib/scout-static";
        hostPath = "/dump/state/scout-static";
        isReadOnly = true;
      };
    };
  };
}
