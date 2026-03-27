{ ... }:
{
  services.surmhosting.services.gitea = {
    host = "gitea.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`gitea.surma.technology`)";
    expose.useTargetHost = true;
    expose.allowedGitHubUsers = [ "surma" ];
  };
}
