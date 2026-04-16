{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # Program modules are auto-loaded from ../../modules/programs

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
    ../../profiles/home-manager/ai.nix

  ];

  secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";

  home.stateVersion = "24.05";
  nix.settings.experimental-features = "nix-command flakes pipe-operators configurable-impure-env";
  home.sessionVariables.FLAKE_CONFIG_URI = "${config.home.homeDirectory}/src/github.com/surma/nixenv#shopisurm";
  defaultConfigs.agents.enable = true;

  programs.starship.settings.custom.cwd.command = lib.mkForce "worldpath";

  allowedUnfreeApps = [ ];

  home.packages = (
    with pkgs;
    [
      # graphite-cli
      keycastr
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.jupyter
      gopls
      bun
      (python3.withPackages (ps: [
        ps.distutils
      ]))
    ]
  );

  defaultConfigs.claude-code.enable = true;
  defaultConfigs.helix.enableSlSyntax = true;

  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;

  programs.opencode.enable = true;
  defaultConfigs.opencode.enable = true;

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

  secrets.items.shopisurm-syncthing.target = "${config.home.homeDirectory}/.local/state/syncthing/key.pem";
  secrets.items.syncthing-relay-token.target = "${config.home.homeDirectory}/.local/state/syncthing-relay/token";

  services.syncthing.enable = true;
  services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
  services.syncthing.key = config.secrets.items.shopisurm-syncthing.target;
  defaultConfigs.syncthing.enable = true;
  defaultConfigs.syncthing.privateRelay.enable = true;
  defaultConfigs.syncthing.privateRelay.tokenFile = config.secrets.items.syncthing-relay-token.target;
  defaultConfigs.syncthing.knownFolders.scratch.enable = true;
  defaultConfigs.syncthing.knownFolders.ebooks.enable = true;
  defaultConfigs.syncthing.knownFolders.surmvault.enable = true;
  defaultConfigs.syncthing.knownFolders.surmvault.path = "${config.home.homeDirectory}/SurmVault";

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
    settings = {
      include = {
        path = "${config.home.homeDirectory}/.config/dev/gitconfig";
      };
      credential."https://*.quick.shopify.io".helper = [
        ""
        "${config.home.homeDirectory}/.config/quick/quick-git-credential.sh"
      ];
      http."https://*.quick.shopify.io/".extraHeader = "X-Requested-With: XMLHttpRequest";
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
    enable = true;
    enableDefaultConfig = false;
    includes = [
      "~/.spin/ssh/include"
      "~/.config/spin/ssh/include"
    ];
  };
}
