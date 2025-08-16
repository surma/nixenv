{
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage;

  writingPrompt = callPackage (import ../apps/writing-prompt) { };
in
{
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

  containers.writing-prompt = rec {
    config = {

      networking.firewall.enable = false;
      environment.systemPackages = [
        writingPrompt
      ];
      environment.variables = {
        NEXT_PUBLIC_VAPID_PUBLIC_KEY = "BOIg72VQ1XXdEFWW_2CcnKGLCQBsKt6x3PZat8ZxIPuI4C_wNcp3AGOeokALwPpPJHx-rPrRnv-RadcXHgG7xyE";
        VAPID_PRIVATE_KEY = "5mobUCGDDker7K57LNubLflpPUf_vuPcR1w2Ro3b4_A";
        JWT_SECRET = "lol123";
        SQLITE_PATH = "/data/sqlite.db";
      };

      systemd.services.writing-prompt = {
        enable = true;
        wantedBy = [ "multi-user.target" ];

        environment = config.environment.variables;

        path = [
          pkgs.nodejs
          pkgs.bash
        ];
        script = ''
          cd ${writingPrompt}/lib/node_modules/writing
          npm start
        '';
        after = [ "multi-user.target" ];
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
}
