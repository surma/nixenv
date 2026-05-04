{ ... }:
{
  services.surmhosting.services.public-brain = {
    host = "public-brain.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`public-brain.surma.technology`)";
    expose.useTargetHost = true;
  };
}
