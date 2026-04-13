{ pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;

  scoutPiAcp = pkgs.writeShellScriptBin "scout-pi-acp" ''
    export GEMINI_API_KEY=dummy
    export PI_PROXY_BASE_URL=${lib.escapeShellArg "https://vendors.llm.surma.technology"}
    export PI_SKIP_VERSION_CHECK=1
    export PATH=${lib.makeBinPath [ inputs.self.packages.${system}.pi-coding-agent pkgs.git pkgs.nix pkgs.openssh ]}:$PATH

    exec ${inputs.self.packages.${system}.pi-acp}/bin/pi-acp "$@"
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

  systemd.tmpfiles.rules = [
    "d /dump/state/scout 0755 surma users - -"
  ];

  services.surmhosting.services.scout.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.scout.container = {
    config = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];
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
          ../../modules/home-manager/mutable-files
          ../../modules/programs/agent-browser
          ../../modules/programs/pi
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
          systemManager = "home-manager";
        };
        users.containeruser = {
          config,
          ...
        }:
        {
          home.username = "containeruser";
          home.homeDirectory = "/home/containeruser";
          home.stateVersion = "25.05";

          home.packages = with pkgs; [
            git
            nix
            openssh
          ];

          programs.home-manager.enable = true;

          programs.ssh = {
            enable = true;
            enableDefaultConfig = false;
            matchBlocks."github.com" = {
              hostname = "github.com";
              user = "git";
              identityFile = [ "~/.ssh/id_surma" ];
              identitiesOnly = true;
              extraOptions.StrictHostKeyChecking = "accept-new";
            };
          };

          programs.pi.enable = true;
          defaultConfigs.pi.enable = true;
          defaultConfigs.pi.extensions.proxy.enable = true;
          defaultConfigs.pi.settings.quietStartup = true;
          defaultConfigs.pi.llmProxy.apiKeyFile = "/var/lib/credentials/scout/llm-proxy-client-key";
        };
      };

      systemd.services.scout = {
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
          pkgs.openssh
        ];
        environment = {
          SCOUT_ACP_COMMAND = "${scoutPiAcp}/bin/scout-pi-acp";
          SCOUT_CWD_TEMPLATE = "/home/containeruser/.local/state/scout/topics/{topic_id}";
          SCOUT_STATE_DIR = "/home/containeruser/.local/state/scout";
        };
        serviceConfig = {
          EnvironmentFile = [
            "/var/lib/credentials/scout/llm-proxy.env"
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
