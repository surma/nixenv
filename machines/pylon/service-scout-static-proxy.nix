{ ... }:
{
  services.surmhosting.services.scout-static = {
    host = "scout-static.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`scout-static.surma.technology`)";
    expose.useTargetHost = true;
    expose.allowedGitHubUsers = [ "surma" ];
  };
}
