{ pkgs, inputs, ... }:
let
  ports = import ./ports.nix;
in
{
  networking.firewall.allowedTCPPorts = [ ports.dump ];

  services.surmhosting.services.dump.expose.port = ports.dump;
  services.surmhosting.services.dump.container = {
    config = {
      system.stateVersion = "25.05";

      systemd.services.dumpd = {
        enable = true;
        description = "Dump service";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${
            inputs.dump.packages.${pkgs.stdenv.hostPlatform.system}.default
          }/bin/dumpd --listen 0.0.0.0:${toString ports.dump} --dir /var/lib/dump --enable-cors";
          User = "containeruser";
          Restart = "always";
        };
      };
    };

    forwardPorts = [
      {
        containerPort = ports.dump;
        hostPort = ports.dump;
        protocol = "tcp";
      }
    ];

    bindMounts.state = {
      mountPoint = "/var/lib/dump";
      hostPath = "/dumpdump";
      isReadOnly = false;
    };
  };
}
