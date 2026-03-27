{ ... }:
{
  services.surmhosting.services.dump = {
    host = "dump.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`dump.surma.technology`)";
    expose.useTargetHost = true;
    expose.allowedGitHubUsers = [ "surma" ];
  };
}
