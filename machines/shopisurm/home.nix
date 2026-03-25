{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # Programs now globally injected
    # ../../modules/programs/telegram

    # Application modules now globally injected
    # ../../modules/home-manager/claude-code
    # ../../modules/home-manager/opencode
    # ../../modules/home-manager/ghostty
    # ../../modules/home-manager/handy

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/physical.nix
    ../../profiles/home-manager/macos.nix
    ../../profiles/home-manager/cloud.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/javascript.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/experiments.nix

  ];

  secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";

  home.stateVersion = "24.05";
  nix.settings.experimental-features = "nix-command flakes pipe-operators configurable-impure-env";
  home.sessionVariables.FLAKE_CONFIG_URI = "${config.home.homeDirectory}/src/github.com/surma/nixenv#shopisurm";

  programs.starship.settings.custom.cwd.command = lib.mkForce "worldpath";

  allowedUnfreeApps = [ ];

  home.packages = (
    with pkgs;
    [
      # graphite-cli
      keycastr
      inputs.self.packages.${pkgs.system}.jupyter
      gopls
      bun
      (python3.withPackages (ps: [
        ps.distutils
      ]))
    ]
  );

  programs.opencode.enable = true;
  defaultConfigs.opencode.enable = true;
  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  defaultConfigs.claude-code.enable = true;
  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;
  defaultConfigs.helix.enableSlSyntax = true;

  programs.ghostty.enable = true;
  defaultConfigs.ghostty.enable = true;
  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;

  customScripts.denix.enable = true;
  customScripts.noti.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.ccp.enable = true;
  customScripts.wallpaper-shuffle.enable = true;
  customScripts.wallpaper-shuffle.asDesktopItem = true;
  customScripts.llm-proxy.enable = true;
  customScripts.oc.enable = true;
  customScripts.ocq.enable = true;

  programs.go.enable = true;

  home.activation.ensureNexusAuthorizedKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    auth_file="$HOME/.ssh/authorized_keys"
    mkdir -p "$HOME/.ssh"
    touch "$auth_file"
    chmod 700 "$HOME/.ssh"
    chmod 600 "$auth_file"

    if ! grep -qxF '${config.secrets.keys.nexus}' "$auth_file"; then
      printf '%s\n' '${config.secrets.keys.nexus}' >> "$auth_file"
    fi
  '';

  programs.git = {
    maintenance.enable = false;
    maintenance.repositories = [
      "${config.home.homeDirectory}/world/git"
    ];
    settings.include = {
      path = "${config.home.homeDirectory}/.config/dev/gitconfig";
    };
  };

  programs.zsh = {
    initContent = ''
      [ -f /opt/dev/dev.sh ] && source /opt/dev/dev.sh
      [[ -f /opt/dev/sh/chruby/chruby.sh ]] && { type chruby >/dev/null 2>&1 || chruby () { source /opt/dev/sh/chruby/chruby.sh; chruby "$@"; } }
      [[ -x /opt/homebrew/bin/brew ]] && eval $(/opt/homebrew/bin/brew shellenv)

      export NIX_PATH=world=$HOME/world/trees/root/src/.meta/substrate/nix
      export PATH=$HOME/.local/state/nix/profiles/wb/bin:$PATH

      [[ -x $HOME/.local/state/tec/profiles/base/current/global/init ]] && eval "$($HOME/.local/state/tec/profiles/base/current/global/init zsh)"
    '';
  };
  programs.ssh = {
    includes = [
      "~/.spin/ssh/include"
      "~/.config/spin/ssh/include"
    ];
  };
}
