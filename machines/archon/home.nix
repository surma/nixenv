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

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/gamedev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/experiments.nix
    ../../profiles/home-manager/ai.nix

    ../../profiles/home-manager/webapps.nix
  ];

  config = {
    programs.brain.enable = lib.mkForce false;
    allowedUnfreeApps = [
      "spotify"
      "slack"
      "discord"
      "claude-code"
      "obsidian"
    ];

    customScripts.toggle-sunset.enable = true;
    customScripts.toggle-sunset.asDesktopItem = true;
    customScripts.bluetooth-fix.enable = true;
    customScripts.bluetooth-fix.asDesktopItem = true;
    customScripts.wallpaper-shuffle.enable = true;
    customScripts.wallpaper-shuffle.asDesktopItem = true;

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

    gtk = {
      enable = true;
      colorScheme = "dark";
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];

    home.stateVersion = "24.05";

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
    programs.whatsapp.enable = true;
    programs.squoosh.enable = true;
    programs.geforce-now.enable = true;
    programs.xbox-remote-play.enable = true;
    programs.obsidian.enable = false;

    programs.wezterm.enable = true;
    programs.wezterm.frontend = "OpenGL";
    programs.wezterm.theme = "dark";
    programs.wezterm.fontSize = 10;
    programs.wezterm.window-decorations = null;
    defaultConfigs.wezterm.enable = true;

    secrets.items.m-config.target = "${config.home.homeDirectory}/.config/m/config.yaml";
    secrets.items.archon-syncthing.target = "${config.home.homeDirectory}/.local/state/syncthing/key.pem";

    services.syncthing.enable = true;
    services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
    services.syncthing.key = config.secrets.items.archon-syncthing.target;
    defaultConfigs.syncthing.enable = true;
    services.syncthing.tray.enable = true;

    # programs.opencode.enable = true;
    # defaultConfigs.opencode.enable = true;
    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;
    # programs.claude-code.enable = true;
    # defaultConfigs.claude-code.enable = true;

    wayland.windowManager.hyprland.enable = true;
    defaultConfigs.hyprland.enable = true;
    # macOS-style Unicode hex input: hold Right Alt, type 1-6 hex digits (or
    # an 8-digit UTF-16 surrogate pair), release Right Alt. Right Alt is
    # reserved for this protocol and consumed before applications see it.
    # Ships as an automatically loaded Fcitx5 module addon, so no input method
    # needs to be selected manually.
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        waylandFrontend = true;
        addons = [ (pkgs.callPackage ../../packages/mac-unicode-hex { }) ];
        settings = {
          inputMethod = {
            GroupOrder."0" = "Default";
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = "us";
              DefaultIM = "keyboard-us";
            };
            "Groups/0/Items/0".Name = "keyboard-us";
          };
          addons.wayland.globalSection."Allow Overriding System XKB Settings" = false;
        };
      };
    };
    # Keep Fcitx's runtime-generated caches alongside the declarative profile
    # and Wayland settings instead of replacing the entire config directory.
    xdg.configFile.fcitx5.recursive = true;

    # Sunshine must follow the actual Hyprland session, not the generic
    # graphical-session.target that GDM also exposes to its greeter user.
    # The NixOS Sunshine unit remains the single service definition; this
    # target dependency supplies the Hyprland-only autostart edge.
    systemd.user.targets."hyprland-session".Unit.Wants = [
      "sunshine.service"
    ];
    programs.hyprlock = {
      enable = true;
      settings = {
        auth.fingerprint.enabled = true;
      };
    };
    # Framework-laptop-specific keyboard backlight controls (the
    # `framework_laptop::kbd_backlight` device only exists on this machine).
    wayland.windowManager.hyprland.extraConfig = ''
      hl.config({
          input = {
              repeat_delay = 225,
              repeat_rate = 25,
          },
      })
      hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%+"), { locked = true, repeating = true })
      hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%-"), { locked = true, repeating = true })
    '';
    programs.waybar.enable = true;
    defaultConfigs.waybar.enable = true;
    programs.hyprsunset.enable = true;
    programs.hyprpaper.enable = true;
    defaultConfigs.hyprpaper.enable = true;

    services.blueman-applet.enable = true;
    services.dunst.enable = true;
    services.hyprpolkitagent.enable = true;

    # Workaround: hyprpolkitagent has crashed on this AMD iGPU because Qt6
    # cannot create an EGL context for the auth window ("qt.qpa.wayland: EGL
    # not available" -> SIGABRT in QSGRenderLoop). When polkit invokes the
    # agent (e.g. for 1Password SSH-key unlock via fingerprint), it dies
    # before showing the prompt, so the unlock silently fails. Forcing the
    # software Qt Quick scenegraph keeps the agent alive and lets the PAM
    # flow (incl. fprintd) run normally. sudo isn't affected because it
    # talks to PAM directly without going through polkit.
    xdg.configFile."systemd/user/hyprpolkitagent.service.d/qt-software.conf".text = ''
      [Service]
      Environment=QT_QUICK_BACKEND=software
    '';
  };
}
