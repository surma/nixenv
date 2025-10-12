{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./nixdev.nix
  ];

  home.packages = with pkgs; [
    git
    gitui
    lazygit
    git-lfs
    tig
    nodejs_24.pkgs.typescript-language-server
    dprint
  ];

  home.file = {
    ".npmrc".source = ../configs/npmrc;
  };

  xdg.configFile."lazygit/config.yml".text = ''
    git:
      autoFetch: false
  '';

  programs.git = {
    enable = true;
    userName = "Surma";
    userEmail = "surma@surma.dev";
    signing = {
      key = "0xE46E2194CAC89068";
      signByDefault = true;
    };
    diff-so-fancy = {
      enable = true;
    };
    extraConfig = {
      init = {
        defaultBranch = "main";
      };
    };
  };
}
