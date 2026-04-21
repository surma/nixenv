{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  brainPkg = inputs.brain.packages.${system}.default;
  brainRepoUrl = "ssh://containeruser@gitea.surma.technology:2222/surma/brain.git";
  brainPath = "/var/lib/brain-serve/brain";

  sshConfig = pkgs.writeText "brain-serve-ssh-config" ''
    Host gitea.surma.technology
      Hostname gitea.nexus.hosts.10.0.0.2.nip.io
      Port 2222
      User containeruser
      IdentityFile /var/lib/brain-serve/.ssh/id_repo_scout
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      HostKeyAlias gitea.nexus.hosts.10.0.0.2.nip.io
      UserKnownHostsFile /var/lib/brain-serve/.ssh/known_hosts
  '';

  gitSshCommand = "ssh -F ${sshConfig}";

  brainSetup = pkgs.writeShellScript "brain-serve-setup" ''
    set -euo pipefail
    export GIT_SSH_COMMAND="${gitSshCommand}"
    if [ ! -d "${brainPath}/.git" ]; then
      echo "Cloning brain repository..."
      ${pkgs.git}/bin/git clone ${brainRepoUrl} ${brainPath}
    fi
    echo "Running brain sync..."
    BRAIN_PATH=${brainPath} ${brainPkg}/bin/brain sync
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /dump/state/brain-serve 0755 surma users - -"
  ];

  services.surmhosting.services.brain-serve.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.brain-serve.expose.port = 8080;
  services.surmhosting.services.brain-serve.container = {
    config = {
      system.stateVersion = "25.05";

      systemd.services.brain-serve-setup = {
        description = "Clone and sync brain repository";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [
          pkgs.git
          pkgs.openssh
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "containeruser";
          ExecStart = brainSetup;
        };
      };

      systemd.services.brain-serve = {
        description = "Brain knowledge base web server";
        wantedBy = [ "multi-user.target" ];
        requires = [ "brain-serve-setup.service" ];
        after = [ "brain-serve-setup.service" ];
        environment.BRAIN_PATH = brainPath;
        serviceConfig = {
          ExecStart = "${brainPkg}/bin/brain serve --port 8080";
          User = "containeruser";
          Restart = "always";
          RestartSec = 5;
        };
      };

      systemd.services.brain-serve-update = {
        description = "Update brain repository";
        path = [
          pkgs.git
          pkgs.openssh
        ];
        environment = {
          GIT_SSH_COMMAND = gitSshCommand;
          BRAIN_PATH = brainPath;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "containeruser";
          ExecStart = "${brainPkg}/bin/brain sync";
        };
      };

      systemd.timers.brain-serve-update = {
        description = "Hourly brain repository update";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };
    };

    bindMounts.state = {
      mountPoint = "/var/lib/brain-serve";
      hostPath = "/dump/state/brain-serve";
      isReadOnly = false;
    };
  };
}
