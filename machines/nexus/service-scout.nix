{ pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  scoutMcpPort = 32445;
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
        ({ config, ... }: {
          systemd.services.scout = let
            opencode = config.home-manager.users.containeruser.programs.opencode.package;
          in {
            description = "Scout Telegram bridge";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            requires = [ "home-manager-containeruser.service" ];
            after = [ "network-online.target" "home-manager-containeruser.service" ];
            path = [
              pkgs.bash
              pkgs.coreutils
              pkgs.git
              pkgs.nix
              pkgs.nodejs_24
              pkgs.openssh
              pkgs.procps
            ];
            environment = {
              SCOUT_ACP_COMMAND = "${opencode}/bin/opencode acp";
              SCOUT_CWD_TEMPLATE = "/home/containeruser/.local/state/scout/topics/{topic_id}";
              SCOUT_MCP_PORT = toString scoutMcpPort;
              SCOUT_STATE_DIR = "/home/containeruser/.local/state/scout";
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
        })
      ];
      system.stateVersion = "25.05";

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
          ../../modules/programs/web-search-cli
          ../../modules/programs/agent-browser
          ../../modules/programs/opencode
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
          systemManager = "home-manager";
        };
        users.containeruser = import ../scout;
      };
    };

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
    };
  };
}
