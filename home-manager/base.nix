{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) callPackage;
in
{

  imports = [
    ../scripts
    ./zellij.nix
    ./ssh-keys.nix
    ./gpg-keys.nix
  ];

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings.experimental-features = "nix-command flakes pipe-operators";
  };
  home.packages =
    with pkgs;
    [
      age
      gawk
      htop
      btop
      mosh
      openssh
      rsync
      tig
      tree
      pinentry-curses
      chafa
      yazi
      fzf
      nushell
      zoxide
    ]
    ++ [ (callPackage (import ../extra-pkgs/dprint) { }) ]
    ++ [
      (callPackage (import ../secrets) { })
    ];

  home.file = {
    ".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry-curses}/bin/pinentry
    '';
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };

  customScripts.hms.enable = true;
  customScripts.denix.enable = true;
  customScripts.ghclone.enable = true;

  programs.home-manager.enable = true;
  programs.bat.enable = true;
  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;
  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
  };
  programs.helix = import ../configs/helix.nix;
  programs.ripgrep.enable = true;
  programs.starship.enable = true;
  programs.gpg.enable = true;
  programs.zsh = import ../configs/zsh.nix;
  programs.ssh = {
    enable = true;
    forwardAgent = true;
    addKeysToAgent = "yes";
    matchBlocks = {
      "*" = {
        identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };
  };
}
