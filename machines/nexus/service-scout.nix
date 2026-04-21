{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  scoutMcpPort = 32445;

  # Hook scripts for Scout topic lifecycle. Copied into the Nix store
  # so they're available at a stable path for SCOUT_HOOKS_DIR.
  scoutHooksDir = pkgs.runCommand "scout-hooks" {} ''
    mkdir -p $out
    cp ${../../assets/scout-hooks/topic-create} $out/topic-create
    cp ${../../assets/scout-hooks/topic-close} $out/topic-close
    chmod +x $out/topic-create $out/topic-close
  '';
in
{
  secrets.items.ssh-keys.command = ''
    mkdir -p /dump/state/scout/.ssh
    chown surma:users /dump/state/scout/.ssh
    chmod 0700 /dump/state/scout/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_surma.pub} /dump/state/scout/.ssh/id_surma.pub
    cat > /dump/state/scout/.ssh/id_surma
    echo >> /dump/state/scout/.ssh/id_surma
    chown surma:users /dump/state/scout/.ssh/id_surma.pub /dump/state/scout/.ssh/id_surma
    chmod 0600 /dump/state/scout/.ssh/id_surma
  '';

  secrets.items.scout-repo-ssh-key.command = ''
    key="$(cat)"

    # Scout container (bind-mounted as /home/containeruser/.ssh inside the container)
    mkdir -p /dump/state/scout/.ssh
    chown surma:users /dump/state/scout/.ssh
    chmod 0700 /dump/state/scout/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} /dump/state/scout/.ssh/id_repo_scout.pub
    chown surma:users /dump/state/scout/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > /dump/state/scout/.ssh/id_repo_scout
    chown surma:users /dump/state/scout/.ssh/id_repo_scout
    chmod 0600 /dump/state/scout/.ssh/id_repo_scout

    # NixOS deploy service (HOME=/var/lib/nixos-deploy)
    mkdir -p /var/lib/nixos-deploy/.ssh
    chmod 0700 /var/lib/nixos-deploy/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} /var/lib/nixos-deploy/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > /var/lib/nixos-deploy/.ssh/id_repo_scout
    chmod 0600 /var/lib/nixos-deploy/.ssh/id_repo_scout
  '';

  secrets.items.scout-telegram-bot-token.command = ''
    mkdir -p /var/lib/scout
    token="$(cat)"
    printf 'SCOUT_TELEGRAM_BOT_TOKEN=%s\n' "$token" > /var/lib/scout/telegram-bot-token.env
    chmod 0600 /var/lib/scout/telegram-bot-token.env
  '';

  secrets.items.scout-telegram-chat-id.command = ''
    mkdir -p /var/lib/scout
    chat_id="$(cat)"
    printf 'SCOUT_TELEGRAM_CHAT_ID=%s\n' "$chat_id" > /var/lib/scout/scout.env
    chmod 0600 /var/lib/scout/scout.env
  '';

  secrets.items.llm-proxy-client-key.command = ''
    mkdir -p /var/lib/scout
    key="$(cat)"
    printf '%s\n' "$key" > /var/lib/scout/llm-proxy-client-key
    chmod 0644 /var/lib/scout/llm-proxy-client-key
  '';

  systemd.tmpfiles.rules = [
    "d /dump/state/scout 0755 surma users - -"
  ];

  services.surmhosting.services.scout.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig.MemoryMax = "16G";
  };

  services.surmhosting.services.scout.container = {
    config = {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        # Module that wires the scout systemd service, with access to the
        # container's evaluated config (needed to reference the wrapped
        # opencode package produced by home-manager).
        (
          { config, ... }:
          {
            # Register the dotenv plugin for opencode — needed so that
            # BRAIN_PATH from the topic .env file reaches brain commands.
            home-manager.users.containeruser.programs.opencode.plugins = {
              "dotenv.js" = builtins.readFile ../../packages/opencode-dotenv-plugin/dotenv.js;
            };

            systemd.services.scout =
              let
                opencode = config.home-manager.users.containeruser.programs.opencode.package;
              in
              {
                description = "Scout Telegram bridge";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" ];
                requires = [ "home-manager-containeruser.service" ];
                after = [
                  "network-online.target"
                  "home-manager-containeruser.service"
                ];
                path = [
                  "/home/containeruser/.nix-profile"
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.git
                  pkgs.nix
                  pkgs.nodejs_24
                  pkgs.openssh
                  pkgs.procps
                  pkgs.sqlite
                ];
                environment = {
                  SCOUT_ACP_COMMAND = "${opencode}/bin/opencode acp";
                  SCOUT_CWD_TEMPLATE = "/home/containeruser/.local/state/scout/topics/{topic_id}";
                  SCOUT_MCP_PORT = toString scoutMcpPort;
                  SCOUT_STATE_DIR = "/home/containeruser/.local/state/scout";
                  SCOUT_HOOKS_DIR = "${scoutHooksDir}";
                  SCOUT_DEFAULT_MODEL = "anthropic/claude-opus-4-6/high";
                  RUST_LOG = "scout=debug";
                };
                serviceConfig = {
                  EnvironmentFile = [
                    "/var/lib/credentials/scout/telegram-bot-token.env"
                    "/var/lib/credentials/scout/scout.env"
                  ];
                  User = "containeruser";
                  Group = "users";
                  WorkingDirectory = "/home/containeruser";
                  Restart = "always";
                  RestartSec = 5;
                  ExecStart = "${inputs.scout.packages.${system}.scout}/bin/scout";
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
        useUserPackages = false;
        sharedModules = [
          ../../modules/features/secrets.nix
          ../../modules/home-manager/agent
          ../../modules/home-manager/brain
          ../../modules/programs/web-search-cli
          ../../modules/programs/agent-browser
          ../../modules/programs/opencode
          ../../modules/programs/parakeet
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
      { modifier = "rw"; node = "/dev/dri/renderD128"; }
      { modifier = "rw"; node = "/dev/dri/card0"; }
    ];

    bindMounts = {
      home = {
        mountPoint = "/home/containeruser";
        hostPath = "/dump/state/scout";
        isReadOnly = false;
      };
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
    };
  };
}
