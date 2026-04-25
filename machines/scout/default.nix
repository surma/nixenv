{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ../../scripts
    ../../modules/home-manager/mutable-files
    ../../modules/defaultConfigs/npm
    ../../modules/home-manager/brain
  ];

  config = {
    home.username = lib.mkDefault "containeruser";
    home.homeDirectory = lib.mkDefault "/home/containeruser";
    home.stateVersion = "25.05";

    nix = {
      package = lib.mkDefault pkgs.nix;
      settings.experimental-features = "nix-command flakes pipe-operators";
    };

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#scout";
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND = "file";
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE = "/var/lib/credentials/scout/gws-credentials.json";

    home.packages = with pkgs; [
      jq
      nodejs_24
      openssh
      ripgrep
      sqlite
      tmux
      inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.gws.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.whatsapp-cli
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.presage-cli
      (python3.withPackages (ps: [
        ps.pip
        ps.virtualenv
      ]))
    ];

    programs.home-manager.enable = true;

    programs.git = {
      enable = true;
      settings = {
        user.name = "Surma";
        user.email = "surma@surma.dev";
        init.defaultBranch = "main";
      };
    };

    defaultConfigs.npm.enable = true;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_repo_scout";
        identitiesOnly = true;
      };
      matchBlocks."gitea.surma.technology" = {
        hostname = "gitea.nexus.hosts.10.0.0.2.nip.io";
        port = 2222;
        user = "containeruser";
        identityFile = "~/.ssh/id_repo_scout";
        identitiesOnly = true;
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
          HostKeyAlias = "gitea.nexus.hosts.10.0.0.2.nip.io";
        };
      };
      matchBlocks."gitea.nexus.hosts.10.0.0.2.nip.io" = {
        hostname = "gitea.nexus.hosts.10.0.0.2.nip.io";
        port = 2222;
        user = "containeruser";
        identityFile = "~/.ssh/id_repo_scout";
        identitiesOnly = true;
        extraOptions.StrictHostKeyChecking = "accept-new";
      };
    };

    programs.agent-browser.enable = true;
    programs.brain.enable = true;
    programs.parakeet.enable = true;

    agent.skills = [
      ../../assets/skills/gws
      ../../assets/skills/nexus-admin
      ../../assets/skills/whatsapp
      ../../assets/skills/signal
    ];

    defaultConfigs.opencode = {
      enable = true;
      llmProxy = {
        manageSecret = false;
        apiKeyFile = "/var/lib/credentials/scout/llm-proxy-client-key";
      };
    };

    home.file = {
      "AGENTS.md".source = ../../assets/AGENTS.md;
      ".local/state/scout/AGENTS.md".source = ./AGENTS.md;
    };

    defaultConfigs.web-search-cli = {
      enable = true;
      llmProxy = {
        manageSecret = false;
        authTokenFile = "/var/lib/credentials/scout/llm-proxy-client-key";
      };
    };
  };
}
