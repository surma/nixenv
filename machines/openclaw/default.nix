{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [ ../../scripts ];

  config = {
    home.username = lib.mkDefault "containeruser";
    home.homeDirectory = lib.mkDefault "/home/containeruser";
    home.stateVersion = "25.05";

    nix = {
      package = lib.mkDefault pkgs.nix;
      settings.experimental-features = "nix-command flakes pipe-operators";
    };

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#openclaw";

    home.packages = with pkgs; [
      git
      openssh
      ripgrep
      (python3.withPackages (ps: [
        ps.pip
        ps.virtualenv
      ]))
    ];

    programs.home-manager.enable = true;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_repo_scout";
        identitiesOnly = true;
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

    defaultConfigs.web-search-cli = {
      enable = true;
      llmProxy = {
        manageSecret = false;
        authTokenFile = "/var/lib/credentials/openclaw/llm-proxy-client-key";
      };
    };
  };
}
