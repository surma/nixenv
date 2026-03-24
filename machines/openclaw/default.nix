{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [ ../../scripts ];

  config = {
    home.username = "containeruser";
    home.homeDirectory = lib.mkForce "/home/containeruser";
    home.stateVersion = "25.05";

    nix = {
      package = lib.mkDefault pkgs.nix;
      settings.experimental-features = "nix-command flakes pipe-operators";
    };

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#openclaw";

    home.packages = with pkgs; [
      git
      openssh
    ];

    programs.home-manager.enable = true;

    defaultConfigs.web-search-cli = {
      enable = true;
      llmProxy = {
        manageSecret = false;
        authTokenFile = "/var/lib/credentials/openclaw/llm-proxy-client-key";
      };
    };
  };
}
