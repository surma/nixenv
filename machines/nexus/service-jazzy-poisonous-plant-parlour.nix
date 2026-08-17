{ pkgs, ... }:
let
  app = pkgs.callPackage ./jazzy-poisonous-plant-parlour { };
in
{
  services.surmhosting.services.jazzy-poisonous-plant-parlour = {
    containerService = {
      wants = [ "secrets.service" ];
      after = [ "secrets.service" ];
    };

    expose.port = 8080;
    container = {
      config = {
        system.stateVersion = "25.05";

        systemd.services.jazzy-poisonous-plant-parlour = {
          description = "Jazz poison question page";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          environment = {
            LISTEN_ADDRESS = "0.0.0.0:8080";
            HOME_ASSISTANT_URL = "http://10.0.0.5:8123";
            HOME_ASSISTANT_ENTITY_ID = "binary_sensor.bean_office_door";
            HOME_ASSISTANT_TOKEN_FILE = "/var/lib/credentials/hassio-token";
          };
          serviceConfig = {
            ExecStart = "${app}/bin/jazzy-poisonous-plant-parlour";
            User = "containeruser";
            Restart = "always";
            RestartSec = 5;
          };
        };
      };

      bindMounts.hassio-token = {
        mountPoint = "/var/lib/credentials/hassio-token";
        hostPath = "/var/lib/scout/hassio-token";
        isReadOnly = true;
      };
    };
  };
}
