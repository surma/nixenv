{
  options,
  config,
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage;
in
{
  imports = [
    ../darwin/base.nix

    ../common/obs
    ../common/obsidian

    ../scripts
    ../secrets
  ];

  system.stateVersion = 5;

  nix.extraOptions = ''
    !include nix.conf.d/shopify.conf
  '';

  programs.obs.enable = true;
  programs.obsidian.enable = true;

  home-manager.users.${config.system.primaryUser} =
    { config, ... }:
    {
      imports = [
        ../common/telegram

        ../home-manager/opencode
        ../home-manager/ghostty
        ../home-manager/llm-key-updater

        ../home-manager/base.nix
        ../home-manager/graphical.nix
        ../home-manager/workstation.nix
        ../home-manager/physical.nix
        ../home-manager/macos.nix
        ../home-manager/cloud.nix
        ../home-manager/nixdev.nix
        ../home-manager/javascript.nix
        ../home-manager/dev.nix
        ../home-manager/experiments.nix
        ../home-manager/unfree-apps.nix

        ../secrets
      ];

      secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";
      secrets.items.llm-proxy-secret.target = "${config.home.homeDirectory}/.config/llm-proxy/secret";
      secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.config/llm-proxy/client-key";

      home.stateVersion = "24.05";
      nix.settings.experimental-features = "nix-command flakes pipe-operators configurable-impure-env";
      home.sessionVariables.FLAKE_CONFIG_URI = "${config.home.homeDirectory}/src/github.com/surma/nixenv#shopisurm";

      allowedUnfreeApps = [ ];

      home.packages = (
        with pkgs;
        [
          # graphite-cli
          keycastr
          jupyter
          (python3.withPackages (ps: [
            ps.distutils
          ]))
        ]
      );

      programs.opencode.enable = true;
      defaultConfigs.opencode.enable = true;
      programs.ghostty.enable = true;
      defaultConfigs.ghostty.enable = true;

      customScripts.denix.enable = true;
      customScripts.noti.enable = true;
      customScripts.ghclone.enable = true;
      customScripts.wallpaper-shuffle.enable = true;
      customScripts.wallpaper-shuffle.asDesktopItem = true;
      customScripts.llm-proxy.enable = true;
      customScripts.get-shopify-key.enable = true;

      # LLM key updater - pushes fresh Shopify keys to nexus
      services.llm-key-updater.enable = true;
      services.llm-key-updater.target = "https://key.llm.surma.technology";
      services.llm-key-updater.secretFile = "${config.home.homeDirectory}/.config/llm-proxy/secret";
      services.llm-key-updater.intervalHours = 8;

      programs.git = {
        maintenance.enable = false;
        maintenance.repositories = [
          "${config.home.homeDirectory}/world/git"
        ];
        settings.include = {
          path = "${config.home.homeDirectory}/.config/dev/gitconfig";
        };
      };

      programs.nushell.extraConfig = ''
        def --env --wrapped dev [...args: string] {
          let tmpfile = (mktemp)
          ^bash -c 'exec 9>"$1"; shift; DEV_SHELL=nushell /opt/dev/bin/dev "$@"' -- $tmpfile ...$args

          for fin in (open $tmpfile | lines | split column ':' -n 2 finalizer value) {
            match $fin.finalizer {
              "cd" => { cd $fin.value }
              "setenv" => {
                let kv = ($fin.value | split column '=' -n 2 key value | first)
                load-env {($kv.key): $kv.value}
              }
            }
          }

          rm -f $tmpfile
        }

        def --env --wrapped devx [...args: string] {
          $env.DEVX_INVOKED = "1"
          dev tools run ...$args
        }

        # Shadowenv hook
        $env.config = ($env.config | upsert hooks.env_change.PWD { |config|
          let existing = $config | get -o hooks.env_change.PWD | default []
          $existing | append {||
             mut flags = ["--json"]

             if ($env.__shadowenv_force_run? | default false) {
              hide-env -i __shadowenv_force_run
              $flags = ($flags | append "--force")
            }

            let result = /Users/surma/.local/state/tec/profiles/base/current/global/bin/shadowenv hook ...$flags | complete
            if $result.exit_code != 0 {
              return
            }

            $result.stdout | from json | get -o exported | default {} | load-env
          }
        })

        $env.__shadowenv_force_run = true
      '';

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
    };
}
