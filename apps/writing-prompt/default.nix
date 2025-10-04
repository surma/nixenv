{
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage writeShellApplication;

  writingPrompt = callPackage (import ./repo) { };

  service = writeShellApplication {
    name = "service";
    runtimeInputs = [
      pkgs.nodejs
      pkgs.bash
    ];
    text = ''
      set -a
      # shellcheck source=/dev/null
      source /data/env
      cd ${writingPrompt}/lib/node_modules/writing
      npm start
    '';
  };
  trigger = writeShellApplication {
    name = "trigger";
    runtimeInputs = [
      pkgs.jwt-cli
      pkgs.nushell
    ];
    text = ''
      # shellcheck source=/dev/null
      source /data/env
      nu ${./trigger.nu}
    '';
  };
in
{
  imports = [
    ../../secrets
  ];
  config = {
    secrets.items.writing-prompt.target = "/var/lib/writing-prompt/env";
    services.traefik.dynamicConfigOptions = {
      http = {
        routers.writing-prompt = {
          rule = "Host(`writing-prompt.surma.technology`)";
          service = "writing-prompt";
        };

        services.writing-prompt.loadBalancer.servers = [
          { url = "http://10.200.0.2:3000"; }
        ];
      };
    };

    networking.nat.enable = true;
    networking.nat.externalInterface = "enp1s0";
    networking.nat.internalInterfaces = [ "ve-*" ];

    containers.writing-prompt = {
      config = {
        system.stateVersion = "25.05";
        networking.firewall.enable = false;
        systemd.services.writing-prompt = {
          enable = true;
          script = "${service}/bin/service";
          wantedBy = [ "multi-user.target" ];
        };
        systemd.services.writing-prompt-trigger = {
          script = "${trigger}/bin/trigger";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
          };
        };
        systemd.timers.writing-prompt-trigger = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Fri 10:00:00";
            Persistent = true;
            Unit = "writing-prompt-trigger.service";
          };
        };
      };
      privateNetwork = true;
      localAddress = "10.200.0.2";
      hostAddress = "10.200.0.1";
      ephemeral = true;
      autoStart = true;
      bindMounts.data = {
        mountPoint = "/data";
        hostPath = "/var/lib/writing-prompt";
        isReadOnly = false;
      };
    };
  };
}
