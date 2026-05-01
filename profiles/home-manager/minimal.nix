{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  pinentry-curses-wrapped = pkgs.writeShellScriptBin "pinentry" ''
    if [ "$TERM" = "xterm-ghostty" ]; then
      export TERM=xterm
    fi
    exec ${pkgs.pinentry-curses}/bin/pinentry "$@"
  '';
in
# A trimmed home-manager profile for headless servers / low-disk machines.
# Sibling to (not layered on top of) `base.nix`, which is the fuller workstation
# baseline. Drops desktop/dev-heavy bits: yazi, chafa, tailscale (system-level
# instead), nodejs/ts-language-server, wl-clipboard, GUI tooling, etc.
{
  imports = [
    ../../scripts
    ../../modules/home-manager/mutable-files
    ../../modules/defaultConfigs/zsh
    ../../modules/defaultConfigs/helix
  ];

  home.username = lib.mkDefault "surma";
  home.homeDirectory = lib.mkDefault "/home/surma";

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings.experimental-features = lib.mkDefault "nix-command flakes pipe-operators";
  };

  home.packages = with pkgs; [
    age
    fd
    fzf
    gawk
    git
    git-lfs
    htop
    just
    mosh
    openssh
    pinentry-curses
    rsync
    tig
    tree
  ];

  home.file.".gnupg/gpg-agent.conf".text = ''
    pinentry-program ${pinentry-curses-wrapped}/bin/pinentry
  '';

  home.sessionVariables.EDITOR = "hx";

  customScripts.denix.enable = true;
  customScripts.ssw_path.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.git-show-commit.enable = true;
  customScripts.timeout.enable = true;

  programs.home-manager.enable = true;
  programs.bat.enable = true;
  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;
  programs.zoxide.enableNushellIntegration = true;
  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
  };
  programs.ripgrep.enable = true;
  programs.starship.enable = true;
  programs.starship.enableNushellIntegration = true;
  programs.starship.settings = {
    add_newline = true;
    format = "${"$"}{custom.cwd} ${"$"}{custom.branch} $hostname $command_duration ${"\n"}$character";
    hostname.style = "bold red";
    hostname.format = "[$ssh_symbol$hostname]($style)";
    command_duration.min_time = 0;
    custom.cwd = {
      command = "ssw_path";
      when = "true";
      format = "[$output]($style)";
      style = "bold cyan";
      disabled = false;
      ignore_timeout = true;
    };
    custom.branch = {
      command = "git branch --show-current";
      when = "test \"$(git rev-parse --is-inside-work-tree 2>&1)\" = true";
      shell = [
        "bash"
        "-"
      ];
      format = "[$output]($style)";
      style = "bold purple";
      disabled = false;
      ignore_timeout = true;
    };
  };
  programs.gpg.enable = true;

  programs.diff-so-fancy.enable = true;
  programs.diff-so-fancy.enableGitIntegration = true;
  programs.git = {
    enable = true;
    settings = {
      user.name = "Surma";
      user.email = "surma@surma.dev";
      init.defaultBranch = "main";
    };
    signing = {
      key = "0xE46E2194CAC89068";
      signByDefault = true;
    };
  };

  programs.nushell.enable = true;
  programs.nushell.shellAliases =
    config.programs.zsh.shellAliases
    |> lib.filterAttrs (
      name: _:
      [
        "cd"
        "ls"
      ]
      |> lib.elem name
      |> (x: !x)
    );

  defaultConfigs.zsh.enable = true;
  defaultConfigs.helix.enable = true;

  services.ssh-agent.enable = true;

  programs.ssh = {
    enableDefaultConfig = false;
    enable = true;
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
        forwardAgent = true;
        identityFile = [
          "${config.home.homeDirectory}/.ssh/id_machine"
          "${config.home.homeDirectory}/.ssh/id_surma"
        ];
      };
    };
  };
}
