# The dev instance of Scout. It runs the `dev` branch of Scout as the bot
# @scout-dev in the "Scout Dev" Space, so features can be tested on the
# real homeserver without touching production Scout. It shares the
# container definition and the credentials with production, but has its
# own home, state, and Matrix account. /dump is read-only.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  scoutContainer = import ./scout-container.nix { inherit pkgs inputs; };
  home = "/dump/state/scout-dev";
in
{
  # Password of the @scout-dev Matrix account.
  secrets.items.scout-dev-matrix-password.command = ''
    mkdir -p /var/lib/scout-dev
    cat > /var/lib/scout-dev/matrix-password
    chown surma:users /var/lib/scout-dev/matrix-password
    chmod 0600 /var/lib/scout-dev/matrix-password
  '';

  # The dev home gets the same SSH keys as production. These lines run after
  # the production lines of the same secrets, which write the source files.
  secrets.items.ssh-keys.command = lib.mkAfter ''
    mkdir -p ${home}/.ssh
    chown surma:users ${home}/.ssh
    chmod 0700 ${home}/.ssh
    install -m 0644 -o surma -g users /dump/state/scout/.ssh/id_surma.pub ${home}/.ssh/id_surma.pub
    install -m 0600 -o surma -g users /dump/state/scout/.ssh/id_surma ${home}/.ssh/id_surma
  '';
  secrets.items.brain-deploy-key.command = lib.mkAfter ''
    mkdir -p ${home}/.ssh
    chown surma:users ${home}/.ssh
    chmod 0700 ${home}/.ssh
    install -m 0644 -o surma -g users /dump/state/scout/.ssh/id_brain.pub ${home}/.ssh/id_brain.pub
    install -m 0600 -o surma -g users /dump/state/scout/.ssh/id_brain ${home}/.ssh/id_brain
  '';
  secrets.items.scout-repo-ssh-key.command = lib.mkAfter ''
    mkdir -p ${home}/.ssh
    chown surma:users ${home}/.ssh
    chmod 0700 ${home}/.ssh
    install -m 0644 -o surma -g users /dump/state/scout/.ssh/id_repo_scout.pub ${home}/.ssh/id_repo_scout.pub
    install -m 0600 -o surma -g users /dump/state/scout/.ssh/id_repo_scout ${home}/.ssh/id_repo_scout
  '';

  systemd.tmpfiles.rules = [
    "d- ${home} 0755 surma users - -"
  ];

  services.surmhosting.services.scout-dev.backend."nixos-container" = scoutContainer {
    scout = inputs.scout-dev.packages.${system}.scout;
    homeHostPath = home;
    matrixUser = "@scout-dev:matrix.surma.technology";
    matrixPasswordFile = "/var/lib/credentials/scout-dev/matrix-password";
    # The "Scout Dev" Space.
    matrixSpace = "!Zy3sLcgHz3Wlgaj2rB:matrix.surma.technology";
    memoryMax = "8G";

    # Voice calls (Element Call), plus the debug recording of the call audio.
    extraEnvironment = {
      SCOUT_MATRIX_VOICE_CALL_COMMAND = "scout-voice-call";
      # Debug: keeps the received caller audio of each call, to tune the
      # keyword spotting on real call audio.
      SCOUT_CALL_DEBUG_RECORD_DIR = "/home/containeruser/.local/state/scout/voice-call-debug";
    };

    # The dev home starts without the Brain clone that the topic-create hook
    # and the brain-sync timer use. Production has a clone from its setup.
    extraModules = [
      {
        systemd.services.brain-clone = {
          description = "Clone the Brain repository once";
          after = [ "home-manager-containeruser.service" ];
          path = [
            pkgs.git
            pkgs.openssh
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "containeruser";
            Group = "users";
          };
          script = ''
            target="$HOME/.local/state/brain"
            if [ -d "$target/.git" ]; then
              exit 0
            fi
            rm -rf "$target"
            # The shared Brain deploy key, as in modules/home-manager/brain.
            git -c core.sshCommand="ssh -i $HOME/.ssh/id_brain -o IdentitiesOnly=yes -o IdentityAgent=none" \
              clone ssh://containeruser@gitea.surma.technology:2222/surma/brain.git "$target"
          '';
        };
        # A timer, so that the clone never blocks the container boot. DNS
        # does not work right after the container starts. Until the clone
        # exists, the timer tries again every 10 minutes.
        systemd.timers.brain-clone = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitInactiveSec = "10min";
          };
        };
      }
    ];

    extraBindMounts.creds-dev = {
      mountPoint = "/var/lib/credentials/scout-dev";
      hostPath = "/var/lib/scout-dev";
      isReadOnly = true;
    };
  };
}
