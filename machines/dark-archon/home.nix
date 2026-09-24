{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/roles/dev.nix
    ../../profiles/home-manager/roles/nixdev.nix
    ../../profiles/home-manager/platform/linux.nix
    ../../profiles/home-manager/gui/fonts.nix
    ../../profiles/home-manager/gui/terminal.nix
    ../../profiles/home-manager/gui/gui-apps.nix
    ../../profiles/home-manager/platform/physical.nix
    ../../profiles/home-manager/gui/hyprland.nix
    # NOTE(surma): Framework-specific (keyboard backlight device). Re-add
    # ../../profiles/home-manager/platform/framework.nix if this is a
    # Framework laptop.
    ../../profiles/home-manager/roles/workstation.nix
    ../../profiles/home-manager/roles/ai.nix

    ../../profiles/home-manager/gui/webapps.nix
  ];

  config = {
    agent.skills = [
      ../../assets/skills/herdr-orchestrator
    ];

    allowedUnfreeApps = [
      "spotify"
      "slack"
      "discord"
      "obsidian"
    ];

    home.packages = (
      with pkgs;
      [
        slack
        nodejs_24
        chromium
        kdePackages.dolphin
        vlc
        qview
      ]
    );

    home.stateVersion = "26.05";

    # Prefer Shopify's canonical managed toolchain, retain /opt/dev only as a
    # migration fallback, and expose the pinned bootstrap tec while Janitor is
    # still converging the managed base profile.
    programs.zsh.initContent =
      lib.mkIf (osConfig.shopify-framework.enable && osConfig.shopify-framework.developerTools.enable)
        (
          lib.mkAfter ''
            if [[ -x "$HOME/.local/state/tec/profiles/base/current/global/init" ]]; then
              eval "$("$HOME/.local/state/tec/profiles/base/current/global/init" zsh)"
            elif [[ -r "/opt/dev/dev.sh" ]]; then
              source "/opt/dev/dev.sh"
            fi

            # Load chruby on first use. Remove this wrapper before sourcing
            # mutable external code so malformed sources cannot recurse.
            if [[ -r "/opt/dev/sh/chruby/chruby.sh" ]] && ! type chruby >/dev/null 2>&1; then
              chruby() {
                local -a saved_args
                saved_args=("$@")
                unfunction chruby 2>/dev/null || {
                  print -u2 -- "chruby initialization wrapper could not remove itself"
                  return 1
                }

                if [[ ! -r "/opt/dev/sh/chruby/chruby.sh" ]]; then
                  print -u2 -- "chruby initialization source is unreadable"
                  return 1
                fi
                if ! source "/opt/dev/sh/chruby/chruby.sh"; then
                  unfunction chruby 2>/dev/null || :
                  unalias chruby 2>/dev/null || :
                  print -u2 -- "chruby initialization failed"
                  return 1
                fi
                if ! (( $+functions[chruby] )); then
                  unfunction chruby 2>/dev/null || :
                  unalias chruby 2>/dev/null || :
                  print -u2 -- "chruby initialization did not define a replacement"
                  return 1
                fi

                chruby "''${saved_args[@]}"
              }
            fi

            if [[ -d "$HOME/.local/state/tec/toolchain/base_profile/bin" ]]; then
              path=("$HOME/.local/state/tec/toolchain/base_profile/bin" $path)
            fi
          ''
        );

    programs.spotify.enable = true;
    # programs.spotify.platform = "wayland";
    programs.discord.enable = true;
    # programs.discord.platform = "wayland";
    programs.telegram.enable = true;
    programs.squoosh.enable = true;
    programs.geforce-now.enable = true;
    programs.xbox-remote-play.enable = true;
    programs.obsidian.enable = false;

    # TODO(surma): Tune for dark-archon's actual display once known. This is
    # archon's 13 inch 2256x1504 panel.
    programs.wezterm.fontSize = 10;

    secrets.items.m-config.target = "${config.home.homeDirectory}/.config/m/config.yaml";

    # programs.opencode.enable = true;
    # defaultConfigs.opencode.enable = true;
    programs.handy.enable = true;
    defaultConfigs.handy.enable = true;

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    # Sunshine must follow the actual Hyprland session, not the generic
    # graphical-session.target that GDM also exposes to its greeter user.
    # The NixOS Sunshine unit remains the single service definition; this
    # target dependency supplies the Hyprland-only autostart edge.
    systemd.user.targets."hyprland-session".Unit.Wants = [
      "sunshine.service"
    ];
  };
}
