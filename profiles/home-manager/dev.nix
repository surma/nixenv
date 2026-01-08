{
  pkgs,
  ...
}:
{
  imports = [
    ./nixdev.nix
  ];

  home.packages = with pkgs; [
    git
    lazygit
    git-lfs
    tig
    nodejs_24.pkgs.typescript-language-server
    dprint
  ];

  home.file = {
    ".npmrc" = {
      source = ../../configs/npmrc;
      mutable = true;
    };
  };

  xdg.configFile."lazygit/config.yml".text = ''
    git:
      autoFetch: false
  '';

  programs.diff-so-fancy.enable = true;
  programs.diff-so-fancy.enableGitIntegration = true;
  programs.git = {
    enable = true;
    settings = {
      user.name = "Surma";
      user.email = "surma@surma.dev";
      init = {
        defaultBranch = "main";
      };
    };
    signing = {
      key = "0xE46E2194CAC89068";
      signByDefault = true;
    };
  };
}
