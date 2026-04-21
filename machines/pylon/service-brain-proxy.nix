{ ... }:
{
  services.surmhosting.services.brain = {
    host = "brain-serve.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`brain.surma.technology`)";
    expose.useTargetHost = true;
    expose.allowedGitHubUsers = [ "surma" ];
  };
}
