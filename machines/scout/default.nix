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
    ../../profiles/home-manager/ai.nix
  ];

  config = {
    home.username = lib.mkDefault "containeruser";
    home.homeDirectory = lib.mkDefault "/home/containeruser";
    home.stateVersion = "25.05";

    nix = {
      package = lib.mkDefault pkgs.nix;
      settings.experimental-features = "nix-command flakes pipe-operators";
    };
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND = "file";
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE = "/var/lib/credentials/scout/gws-credentials.json";
    home.sessionVariables.HASSIO_URL = "http://10.0.0.5:8123";
    home.sessionVariables.RMAPI_CONFIG = "${config.home.homeDirectory}/.config/rmapi/rmapi.conf";
    home.sessionVariables.NETLIFY_AUTH_TOKEN_FILE = "/var/lib/credentials/scout/netlify-token";

    fonts.fontconfig.enable = true;

    home.packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
      noto-fonts
      jq
      nodejs_24
      openssh
      percollate
      ripgrep
      sqlite
      tmux
      zellij
      inputs.bandsnatch.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.gws.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.whatsapp-cli
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.presage-cli
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.homeassistant-cli
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rmapi
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
    defaultConfigs.agents = {
      enable = true;
      extraFiles = [ ./AGENTS.md ];
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        identityFile = "~/.ssh/id_repo_scout";
      };
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

    # programs.agent-browser is enabled by the AI profile.
    programs.brain.enable = true;

    # Skills from the AI profile (brainstorming, planning, debugging,
    # surma-writer, triple-helix, preact-signals, web-development,
    # orchestrator, bro, rust) are inherited via the
    # import above.  Only Scout-specific skills are listed here.
    agent.skills = [
      ../../assets/skills/cloudflare
      ../../assets/skills/gws
      ../../assets/skills/hetzner
      ../../assets/skills/hedgedoc
      ../../assets/skills/homeassistant
      ../../assets/skills/music
      ../../assets/skills/netlify
      ../../assets/skills/nexus-admin
      ../../assets/skills/remarkable
      ../../assets/skills/signal
      ../../assets/skills/tts
      ../../assets/skills/web-to-epub
      ../../assets/skills/whatsapp
    ];

    defaultConfigs.pi = {
      enable = true;
      llmProxy = {
        apiKeyFile = "/var/lib/credentials/scout/llm-proxy-client-key";
      };
      openRouter.keyFile = lib.mkForce "/var/lib/credentials/scout/openrouter-api-key";
      extensions.proxy.enable = true;
      extensions.dotenv.enable = true;
      extensions.contextUsage.enable = true;
      settings = {
        defaultProvider = "openai";
        defaultModel = "gpt-5.6-luna";
        defaultThinkingLevel = "max";
      };
    };

    # The host decrypts this secret and mounts it read-only into Scout.
    home.activation.secrets = lib.mkForce (
      lib.hm.dag.entryAfter [ "write-boundary" ] ""
    );

    home.activation.rmapi-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      srcFile="/var/lib/credentials/scout/rmapi/rmapi.conf"
      destDir="${config.home.homeDirectory}/.config/rmapi"
      if [ -f "$srcFile" ]; then
        mkdir -p "$destDir"
        cp "$srcFile" "$destDir/rmapi.conf"
        chmod 0600 "$destDir/rmapi.conf"
      fi
    '';

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
