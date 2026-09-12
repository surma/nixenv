{ pkgs, ... }:
let
  baseUrl = "https://gist.surma.technology";
  stateDirectory = "/var/lib/opengist";
  githubSecretDirectory = "/var/lib/hedgedoc2-secrets";
  githubEnvironmentFile = "${githubSecretDirectory}/github.env";
  configFile = pkgs.writeText "opengist-config.yml" ''
    external-url: ${baseUrl}
    opengist-home: ${stateDirectory}
    db-uri: file:${stateDirectory}/opengist.db
    http.host: 0.0.0.0
    http.port: 6157
    http.git-enabled: true
    api.enabled: true
    ssh.git-enabled: disabled
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /dump/state/opengist 0750 surma users - -"
  ];

  services.surmhosting.services.gist = {
    containerService = {
      wants = [ "secrets.service" ];
      after = [ "secrets.service" ];
    };

    expose.apps.gist = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ "gist.surma.technology" ];
      ports = [
        {
          port = 6157;
          hostname = "gist";
        }
      ];
    };

    container = {
      bindMounts = {
        state = {
          mountPoint = stateDirectory;
          hostPath = "/dump/state/opengist";
          isReadOnly = false;
        };
        github-secret = {
          mountPoint = githubSecretDirectory;
          hostPath = githubSecretDirectory;
          isReadOnly = true;
        };
      };

      config = {
        system.stateVersion = "25.05";
        environment.systemPackages = [ pkgs.git ];

        systemd.tmpfiles.rules = [
          "d ${stateDirectory} 0750 containeruser users - -"
        ];

        systemd.services.opengist = {
          description = "OpenGist pastebin";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          path = [ pkgs.git ];
          serviceConfig = {
            ExecStart = "${pkgs.opengist}/bin/opengist --config ${configFile} start";
            EnvironmentFile = [ githubEnvironmentFile ];
            WorkingDirectory = stateDirectory;
            User = "containeruser";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
  };
}
