{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (pkgs) callPackage;

  not = x: !x;

  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
in
{

  imports = [
    ../scripts
    ../secrets
    ./zellij.nix

    ../home-manager/nushell
  ];

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings.experimental-features = lib.mkDefault "nix-command flakes pipe-operators";
  };

  home.packages = with pkgs; [
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
    dprint
    fd
  ];

  home.file = {
    ".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry-curses}/bin/pinentry
    '';
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };

  customScripts.denix.enable = true;
  customScripts.ssw_path.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.nix-build-pkg.enable = true;
  customScripts.build-nixpkg-pkg.enable = true;
  customScripts.git-show-commit.enable = true;

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
  programs.starship.settings = {
    add_newline = true;

    format = ''${"$"}{custom.cwd} $git_branch $hostname ${"\n"}$character'';

    git_branch.format = "[$branch]($style)";
    hostname.style = "bold red";
    hostname.format = "[$ssh_symbol$hostname]($style)";
    custom.cwd = {
      command = "ssw_path";
      when = "true";
      format = "[$output]($style)";
      style = "bold cyan";
      disabled = false;
      ignore_timeout = true;
    };
  };
  programs.gpg.enable = true;
  programs.zsh = (callPackage (import ../configs/zsh.nix) { }).config;
  programs.nushell.enable = true;
  programs.nushell.package = pkgs-unstable.nushell;
  programs.nushell.shellAliases =
    config.programs.zsh.shellAliases
    |> lib.filterAttrs (
      name: _:
      [
        "cd"
        "ls"
      ]
      |> lib.elem name
      |> not
    );

  programs.ssh = {
    enable = true;
    forwardAgent = true;
    addKeysToAgent = "yes";
    matchBlocks = {
      "*" = {
        identityFile = [
          "${config.home.homeDirectory}/.ssh/id_machine"
          "${config.home.homeDirectory}/.ssh/id_surma"
        ];
      };
    };
  };
}
