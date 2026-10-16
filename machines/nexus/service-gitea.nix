{ ... }:
let
  ips = import ../../ips.nix;
  ports = import ./ports.nix;
  # nixos-admin's webhook endpoint on the internal entrypoint (no login;
  # managed containers may reach :8081, see default.nix). Repo webhooks for
  # app deploys use http://${adminHooksHost}:8081/hooks/gitea.
  adminHooksHost = "admin.nexus.hosts.${ips.hosts.nexus.ip}.nip.io";
in
{
  networking.firewall.allowedTCPPorts = [ ports.giteaSsh ];

  # Public: anyone can browse and clone public repos over HTTPS without the
  # surmhosting login; private repos still need a Gitea account.
  services.surmhosting.services.gitea.expose.apps.gitea = {
    access.mode = "public";
    internal.access = "trusted-network";
    public.aliases = [ "gitea.surma.technology" ];
    ports = [
      {
        port = 8080;
        hostname = "gitea";
      }
    ];
  };
  services.surmhosting.services.gitea.backend."nixos-container" = {
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
      # Anonymous visitors may view (and clone) public repos.
      services.gitea.settings.service.REQUIRE_SIGNIN_VIEW = false;
      # Gitea blocks webhooks to private addresses by default (`external`
      # only); also allow nixos-admin's hook host (resolves to the LAN
      # address of nexus).
      services.gitea.settings.webhook.ALLOWED_HOST_LIST = "external,${adminHooksHost}";
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
