{
  pkgs,
  lib,
  ...
}:
with lib;
let
  lazygitConfig = ''
    git:
      autoFetch: false
      fetchAll: false
  '';
in
{
  imports = [
    ./nixdev.nix
    ../../modules/defaultConfigs/npm
  ];

  home.packages = with pkgs; [
    git
    lazygit
    git-lfs
    tig
    nodejs_24.pkgs.typescript-language-server
    dprint
  ];

  defaultConfigs.npm.enable = true;

  home.file = mkMerge [
    (mkIf pkgs.stdenv.isDarwin {
      "Library/Application Support/lazygit/config.yml".text = lazygitConfig;
    })
    (mkIf pkgs.stdenv.isLinux {
      ".config/lazygit/config.yml".text = lazygitConfig;
    })
  ];

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
