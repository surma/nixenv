{
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage writeShellApplication;

  writingPrompt = callPackage (import ./repo) { };

  writingPromptService = writeShellApplication {
    name = "write-prompt-service";
    text = ''
      set -a
      # shellcheck source=/dev/null
      source /data/env
      cd ${writingPrompt}/lib/node_modules/writing
      npm start
    '';
  };
  timer = writeShellApplication {
    name = "timer";
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
    secrets.identity = "/home/surma/.ssh/id_machine";
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
          script = "${writingPromptService}/bin/writing-prompt-service";
          wantedBy = [ "multi-user.target" ];
        };
        systemd.services.timer = {
          script = "${timer}/bin/timer";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
          };
        };
        systemd.timers."timer" = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Mon 10:00:00";
            Persistent = true;
            Unit = "timer.service";
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
