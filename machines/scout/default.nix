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
    home.sessionVariables.HASSIO_URL = "http://10.0.0.5:8123";

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
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.homeassistant-cli
      spotify-player
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
      ../../assets/skills/homeassistant
      ../../assets/skills/nexus-admin
      ../../assets/skills/surma-writer
      ../../assets/skills/whatsapp
      ../../assets/skills/signal
      ../../assets/skills/brainstorming
      ../../assets/skills/planning
      ../../assets/skills/debugging
      ../../assets/skills/music
    ];

    defaultConfigs.opencode = {
      enable = true;
      llmProxy = {
        manageSecret = false;
        apiKeyFile = "/var/lib/credentials/scout/llm-proxy-client-key";
      };
    };

    programs.opencode.plugins."bash-jobs.js" = builtins.readFile ./plugins/bash-jobs.js;

    home.activation.hassio-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      tokenFile="/var/lib/credentials/scout/hassio-token"
      if [ -f "$tokenFile" ]; then
        mkdir -p "${config.home.homeDirectory}/.hassio-cli"
        token="$(cat "$tokenFile")"
        printf '{"url":"http://10.0.0.5:8123","token":"%s"}\n' "$token" \
          > "${config.home.homeDirectory}/.hassio-cli/settings.json"
        chmod 0600 "${config.home.homeDirectory}/.hassio-cli/settings.json"
      fi
    '';

    home.activation.spotify-credentials = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      credDir="/var/lib/credentials/scout"
      cacheDir="${config.home.homeDirectory}/.cache/spotify-player"
      if [ -f "$credDir/spotify-credentials.json" ]; then
        mkdir -p "$cacheDir"
        cp "$credDir/spotify-credentials.json" "$cacheDir/credentials.json"
        cp "$credDir/spotify-client-token.json" "$cacheDir/user_client_token.json"
        chmod 0600 "$cacheDir/credentials.json" "$cacheDir/user_client_token.json"
      fi
    '';

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
