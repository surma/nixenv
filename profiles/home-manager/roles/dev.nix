{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  lazygitConfig = ''
    git:
      autoFetch: false
      fetchAll: false
    os:
      copyToClipboardCmd: 'printf "\033]52;c;%s\007" "$(printf %s "{{text}}" | base64 | tr -d "\n")" > /dev/tty'
  '';
in
{
  imports = [
    ./nixdev.nix
    ../../../modules/defaultConfigs/npm
  ];

  home.packages = with pkgs; [
    gh
    git
    lazygit
    git-lfs
    tig
    typescript-language-server
    dprint
    just
    nodejs_24
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

  # Identity, signing and diff-so-fancy live in core.nix. This is the
  # developer-machine addition only.
  programs.git.settings.include.path = "${config.home.homeDirectory}/.config/dev/gitconfig";
}
