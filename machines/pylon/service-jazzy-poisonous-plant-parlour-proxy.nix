{ ... }:
{
  services.surmhosting.services.jazzy-poisonous-plant-parlour = {
    host = "jazzy-poisonous-plant-parlour.nexus.hosts.100.83.198.90.nip.io";
    expose.port = 80;
    expose.rule = "Host(`jazzy-poisonous-plant-parlour.surma.technology`)";
    expose.useTargetHost = true;
  };
}
