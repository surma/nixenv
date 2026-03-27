{ ... }:
let
  ports = import ./ports.nix;
in
{
  secrets.items.nexus-redis.target = "/var/lib/redis/password";

  networking.firewall.allowedTCPPorts = [ ports.redis ];

  services.surmhosting.services.redis.container = {
    config = {
      system.stateVersion = "25.05";

      services.redis.servers.default = {
        enable = true;
        port = ports.redis;
        bind = "0.0.0.0";
        requirePassFile = "/var/lib/credentials/redis/password";
      };
    };

    forwardPorts = [
      {
        containerPort = ports.redis;
        hostPort = ports.redis;
        protocol = "tcp";
      }
    ];

    bindMounts = {
      state = {
        mountPoint = "/var/lib/redis-default";
        hostPath = "/dump/state/redis";
        isReadOnly = false;
      };
      creds = {
        mountPoint = "/var/lib/credentials/redis";
        hostPath = "/var/lib/redis";
        isReadOnly = true;
      };
    };
  };
}
