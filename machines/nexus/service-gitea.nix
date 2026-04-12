{ ... }:
let
  ports = import ./ports.nix;
in
{
  networking.firewall.allowedTCPPorts = [ ports.giteaSsh ];

  services.surmhosting.services.gitea.expose.port = 8080;
  services.surmhosting.services.gitea.container = {
    config = {
      system.stateVersion = "25.05";

      services.gitea.enable = true;
      services.gitea.stateDir = "/dump/state/gitea";
      services.gitea.user = "containeruser";
      services.gitea.settings.server.HTTP_PORT = 8080;
      services.gitea.settings.server.DOMAIN = "gitea.surma.technology";
      services.gitea.settings.server.ROOT_URL = "https://gitea.surma.technology/";
      services.gitea.settings.server.SSH_DOMAIN = "gitea.surma.technology";
      services.gitea.settings.server.SSH_PORT = ports.giteaSsh;
      services.gitea.settings.server.START_SSH_SERVER = true;
      services.gitea.settings.database.SQLITE_JOURNAL_MODE = "WAL";
      # services.openssh.enable = true;
    };

    forwardPorts = [
      {
        containerPort = ports.giteaSsh;
        hostPort = ports.giteaSsh;
        protocol = "tcp";
      }
    ];

    bindMounts.state = {
      mountPoint = "/dump/state/gitea";
      hostPath = "/dump/state/gitea";
      isReadOnly = false;
    };
  };
}
