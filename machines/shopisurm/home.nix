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
  home.sessionVariables = {
    HASSIO_URL = "http://10.0.0.5:8123";
    SHOPIFY_AI_RTK = "0";
  };
  nix.settings.extra-experimental-features = "configurable-impure-env";
  defaultConfigs.agents = {
    enable = true;
    extraSections = [
      ''
        ## Shopify World git workflow

        When working in repositories under `~/world`, always use `gt` for repository operations instead of raw `git`, including read-only commands like status, diff, and log. If `gt` cannot do something, stop and ask before using `git` directly.
        Some `gt` subcommands, such as `gt push`, are only thin wrappers around raw Git operations. Do not use them as a workaround for the “use `gt` instead of `git`” rule. For Graphite/stack workflows, use Graphite-native commands such as `gt create`, `gt submit`, `gt reorder`, and `gt restack`. If the right Graphite command is unclear, stop and ask instead of falling back to Git or Git-like passthrough commands.
      ''
    ];
  };
  programs.gitea-cli.enable = true;

  # Shopify Tool Gateway Pi extension (shopisurm only); pi-config stays the base everywhere.
  defaultConfigs.pi.extraPackages = [
    { source = "https://github.com/shopify-playground/pi-tool-gateway-extension"; }
  ];

  agent.skills = [
    ../../assets/skills/agent-slack-write
    ../../assets/skills/commitsit
    ../../assets/skills/wcb
  ];

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
      (inputs.nixpkgs-unstable.legacyPackages.${stdenv.hostPlatform.system}.lima.override {
        withAdditionalGuestAgents = true;
      })
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

  programs.surma-noti.enable = true;
  secrets.items.scout-hassio-token.command = ''
    config_dir="${config.home.homeDirectory}/.hassio-cli"
    install -d -m 0700 "$config_dir"
    token="$(cat)"
    printf '{"url":"http://10.0.0.5:8123","token":"%s"}\n' "$token" > "$config_dir/settings.json"
    chmod 0600 "$config_dir/settings.json"
  '';
  customScripts.denix.enable = true;
  customScripts.ghapprove.enable = true;
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
