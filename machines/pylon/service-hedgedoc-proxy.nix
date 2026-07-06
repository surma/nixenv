{ ... }:
{
  services.surmhosting.services.hedgedoc = {
    host = "hedgedoc.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`hedgedoc.surma.technology`)";
    expose.useTargetHost = true;
    expose.allowedGitHubUsers = [ "surma" ];
  };
}
