{ pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  brainPkg = inputs.brain.packages.${system}.default;
  brainRepoUrl = "ssh://containeruser@gitea.surma.technology:2222/surma/brain.git";
  brainPath = "/var/lib/brain-serve/brain";

  sshConfig = pkgs.writeText "brain-serve-ssh-config" ''
    Host gitea.surma.technology
      Hostname 10.0.0.2
      Port 2222
      User containeruser
      IdentityFile /var/lib/brain-serve/.ssh/id_repo_scout
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      HostKeyAlias gitea.nexus.hosts.10.0.0.2.nip.io
      UserKnownHostsFile /var/lib/brain-serve/.ssh/known_hosts
  '';

  gitSshCommand = "ssh -F ${sshConfig}";

  brainSync = pkgs.writeShellScript "brain-serve-sync" ''
    set -euo pipefail
    export GIT_SSH_COMMAND="${gitSshCommand}"
    if [ ! -d "${brainPath}/.git" ]; then
      echo "Cloning brain repository..."
      rm -rf "${brainPath}"
      ${pkgs.git}/bin/git clone ${brainRepoUrl} ${brainPath}
    fi
    echo "Running brain sync..."
    BRAIN_SKIP_QMD=1 BRAIN_PATH=${brainPath} ${brainPkg}/bin/brain sync
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

      # brain-serve is NOT wantedBy multi-user.target — it's started by
      # a timer 10s after boot. This prevents the slow clone/sync from
      # blocking container boot and causing the host container unit to
      # time out during switch-to-configuration.
      systemd.services.brain-serve = {
        description = "Brain knowledge base web server";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [
          pkgs.git
          pkgs.openssh
        ];
        environment = {
          BRAIN_PATH = brainPath;
          GIT_SSH_COMMAND = gitSshCommand;
          HOME = "/var/lib/brain-serve";
          GIT_AUTHOR_NAME = "Surma";
          GIT_AUTHOR_EMAIL = "surma@surma.dev";
          GIT_COMMITTER_NAME = "Surma";
          GIT_COMMITTER_EMAIL = "surma@surma.dev";
        };
        serviceConfig = {
          ExecStartPre = "${brainSync}";
          ExecStart = "${brainPkg}/bin/brain serve --port 8080";
          User = "containeruser";
          Restart = "always";
          RestartSec = 30;
          TimeoutStartSec = 900;
        };
      };

      # Start brain-serve 10s after boot, giving the container network
      # time to come up without blocking the boot sequence.
      systemd.timers.brain-serve = {
        description = "Delayed start for brain-serve";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10s";
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
          HOME = "/var/lib/brain-serve";
          GIT_AUTHOR_NAME = "Surma";
          GIT_AUTHOR_EMAIL = "surma@surma.dev";
          GIT_COMMITTER_NAME = "Surma";
          GIT_COMMITTER_EMAIL = "surma@surma.dev";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "containeruser";
          ExecStart = "${brainSync}";
          TimeoutStartSec = 900;
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
