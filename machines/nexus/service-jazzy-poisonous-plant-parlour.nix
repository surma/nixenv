{ ... }:
let
  ips = import ../../ips.nix;
in
{
  nexus.apps.jazzy-poisonous-plant-parlour = {
    flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/jazzy-poisonous-plant-parlour";

    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    secrets.hassio-token = "/var/lib/scout/hassio-token";

    env = {
      LISTEN_ADDRESS = "0.0.0.0:8080";
      HOME_ASSISTANT_URL = "http://${ips.hosts.homeassistant.ip}:8123";
      HOME_ASSISTANT_OFFICE_DOOR_ENTITY_ID = "binary_sensor.bean_office_door";
      HOME_ASSISTANT_GARDEN_DOOR_ENTITY_ID = "binary_sensor.garden_door_sensor";
      HOME_ASSISTANT_TOKEN_FILE = "%d/hassio-token";
    };

    containerConfig = {
      systemd.services.app.serviceConfig.LoadCredential = [
        "hassio-token:/run/app-secrets/hassio-token"
      ];
    };

    expose.apps.jazzy = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ "jazzy-poisonous-plant-parlour.surma.technology" ];
      ports = [
        {
          port = 8080;
          hostname = "jazzy-poisonous-plant-parlour";
        }
      ];
    };
  };
}
