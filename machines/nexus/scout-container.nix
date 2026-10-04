# The NixOS container of one Scout instance. Production Scout
# (service-scout.nix) and the dev instance (service-scout-dev.nix) share this
# definition. They differ only in the arguments below.
{
  pkgs,
  inputs,
}:
{
  # The Scout package that the instance runs.
  scout,
  # The host directory that becomes /home/containeruser in the container.
  homeHostPath,
  # The Matrix account of the bot, and the password file in the container.
  matrixUser,
  matrixPasswordFile,
  # Scout acts only in rooms of this Space.
  matrixSpace,
  memoryMax,
  extraAllowedDevices ? [ ],
  extraBindMounts ? { },
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  ips = import ../../ips.nix;
  scoutApiPort = 32445;

  # Hook scripts for Scout topic lifecycle. Copied into the Nix store
  # so they're available at a stable path for SCOUT_HOOKS_DIR.
  scoutHooksDir = pkgs.runCommand "scout-hooks" { } ''
    mkdir -p $out
    cp ${../../assets/scout-hooks/topic-create} $out/topic-create
    cp ${../../assets/scout-hooks/topic-close} $out/topic-close
    chmod +x $out/topic-create $out/topic-close
  '';
in
{
  service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig.MemoryMax = memoryMax;
  };

  config = {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      # Module that wires the scout systemd service, with access to the
      # container's evaluated config (needed to reference the wrapped
      # pi package produced by home-manager).
      (
        { config, ... }:
        {
          systemd.services.scout =
            let
              pi = config.home-manager.users.containeruser.programs.pi.package;
            in
            {
              description = "Scout Matrix bridge";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              requires = [ "home-manager-containeruser.service" ];
              after = [
                "network-online.target"
                "home-manager-containeruser.service"
              ];
              path = [
                # home-manager.useUserPackages puts the user environment here
                # rather than in ~/.nix-profile. The hosting module enables this.
                "/etc/profiles/per-user/containeruser"
                pkgs.bash
                pkgs.coreutils
                pkgs.git
                pkgs.nix
                pkgs.nodejs_24
                pkgs.openssh
                pkgs.procps
                pkgs.sqlite
                pkgs.zellij
              ];
              environment = {
                SCOUT_PI_COMMAND = "${pi}/bin/pi";
                SCOUT_CWD_TEMPLATE = "/home/containeruser/.local/state/scout/topics/{topic_id}";
                SCOUT_API_PORT = toString scoutApiPort;
                SCOUT_STATE_DIR = "/home/containeruser/.local/state/scout";
                SCOUT_HOOKS_DIR = "${scoutHooksDir}";
                SCOUT_LOG = "scout=debug";
                # Scout talks to Surma through the Matrix homeserver on
                # Nexus. The default model lives in Scout's state.db; set it
                # with `!model default` in the "Scout status" room.
                # The homeserver URL uses the internal Traefik entrypoint,
                # so traffic stays on Nexus.
                SCOUT_MATRIX_HOMESERVER = "http://matrix.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081";
                SCOUT_MATRIX_USER = matrixUser;
                SCOUT_MATRIX_PASSWORD_FILE = matrixPasswordFile;
                SCOUT_MATRIX_ALLOWED_USERS = "@surma:matrix.surma.technology";
                # Scout acts only in rooms of this Space.
                SCOUT_MATRIX_SPACE = matrixSpace;
              };
              serviceConfig = {
                User = "containeruser";
                Group = "users";
                WorkingDirectory = "/home/containeruser";
                Restart = "always";
                RestartSec = 5;
                ExecStart = pkgs.writeShellScript "scout-start" ''
                  PI_CONFIG_DIR="$HOME/.pi/agent/git/github.com/surma/pi-config"
                  if [ -d "$PI_CONFIG_DIR/.git" ]; then
                    ${pkgs.git}/bin/git -C "$PI_CONFIG_DIR" pull --ff-only
                  fi
                  exec ${scout}/bin/scout
                '';
              };
            };

          # Weekly cleanup of retired topic workspaces.
          # Scout writes a .retired marker into topic directories on close;
          # this timer removes those directories after they've sat for 7+ days.
          systemd.services.scout-cleanup = {
            description = "Remove retired Scout topic workspaces";
            serviceConfig = {
              Type = "oneshot";
              User = "containeruser";
              Group = "users";
              ExecStart = pkgs.writeShellScript "scout-cleanup" ''
                ${pkgs.findutils}/bin/find /home/containeruser/.local/state/scout/topics \
                  -maxdepth 2 -name .retired -mtime +7 -printf '%h\n' \
                | while read -r dir; do
                    echo "removing retired workspace: $dir"
                    rm -rf "$dir"
                  done
              '';
            };
          };
          systemd.timers.scout-cleanup = {
            description = "Weekly cleanup of retired Scout topic workspaces";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "weekly";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };
          # Periodic brain sync on the main clone.
          # Keeps documents and the SQLite index/embeddings fresh so new
          # topic worktrees start with an up-to-date DB copy.
          systemd.services.brain-sync = {
            description = "Sync Brain knowledge base (main clone)";
            path = [
              pkgs.git
              pkgs.openssh
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "containeruser";
              Group = "users";
              Environment = "BRAIN_PATH=/home/containeruser/.local/state/brain";
              ExecStart = "${inputs.brain.packages.${system}.default}/bin/brain sync";
            };
          };
          systemd.timers.brain-sync = {
            description = "Hourly Brain knowledge base sync";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "hourly";
              Persistent = true;
              RandomizedDelaySec = "5m";
            };
          };
        }
      )
    ];
    system.stateVersion = "25.05";

    hardware.graphics.enable = true;

    # GitHub's published host key. Pi clones its config from GitHub over
    # SSH at each start, and a new home has no known_hosts entry for it.
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    users.users.containeruser = {
      isNormalUser = true;
      group = "users";
      home = "/home/containeruser";
    };

    systemd.tmpfiles.rules = [
      "d /home/containeruser 0755 containeruser users - -"
    ];

    home-manager = {
      useGlobalPkgs = true;
      # useUserPackages defaults to true through the hosting module.
      sharedModules = [
        ../../modules/features/secrets.nix
        ../../modules/home-manager/agent
        ../../modules/home-manager/brain
        ../../modules/programs/web-search-cli
        ../../modules/programs/agent-browser
        ../../modules/programs/pi
        ../../modules/programs/surma-noti
      ];
      extraSpecialArgs = {
        inherit inputs;
        inherit system;
        systemManager = "home-manager";
      };
      users.containeruser = import ../scout;
    };
  };

  allowedDevices = [
    {
      modifier = "rw";
      node = "/dev/dri/renderD128";
    }
    {
      modifier = "rw";
      node = "/dev/dri/card0";
    }
  ]
  ++ extraAllowedDevices;

  bindMounts = {
    home = {
      mountPoint = "/home/containeruser";
      hostPath = homeHostPath;
      isReadOnly = false;
    };
    # The shared credentials of all Scout instances.
    creds = {
      mountPoint = "/var/lib/credentials/scout";
      hostPath = "/var/lib/scout";
      isReadOnly = true;
    };
    dri = {
      mountPoint = "/dev/dri";
      hostPath = "/dev/dri";
      isReadOnly = false;
    };
    dump = {
      mountPoint = "/dump";
      hostPath = "/dump";
      isReadOnly = true;
    };
  }
  // extraBindMounts;
}
