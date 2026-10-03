{
  config,
  lib,
  pkgs,
  ...
}:
# My Wayland desktop shell: the bar, the lock screen, notifications, the
# portal, and the input method. This is the user half of
# profiles/nixos/gui/wayland.nix, so machines import both.
let
  # The same default wallpaper as swaybg (./niri.nix, ./sxwm.nix) and hyprpaper.
  wallpapers = ../../../assets/wallpapers;
  defaultWallpaper = builtins.readDir wallpapers |> lib.attrNames |> (names: builtins.head names);
  defaultWallpaperPath = "${wallpapers}/${defaultWallpaper}";
in
{
  imports = [
    ./hyprland.nix
    ./niri.nix
    ./sxwm.nix
  ];

  programs.eww = {
    enable = true;
    systemd.enable = true;
  };
  defaultConfigs.eww.enable = true;

  # The sunset button (toggle-sunset) starts and stops this unit. wlsunset
  # uses wlr-gamma-control, which niri, Hyprland, and SXWM implement. With
  # sunrise and sunset both at 00:00 the day has zero length, so wlsunset
  # holds the low temperature all day. It needs -T > -t, hence 4001.
  systemd.user.services.night-light = {
    Unit = {
      Description = "Night light";
      PartOf = [ config.wayland.systemd.target ];
    };
    Service.ExecStart = "${pkgs.wlsunset}/bin/wlsunset -t 4000 -T 4001 -S 00:00 -s 00:00";
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      auth.fingerprint.enabled = true;
      # Without widgets hyprlock renders nothing, so a locked session is
      # just a black screen. One input field per output (`monitor = ""`)
      # accepts both the password and the fingerprint sensor. The color
      # shows if the wallpaper cannot load.
      background = [
        {
          monitor = "";
          path = defaultWallpaperPath;
          color = "rgba(25, 20, 20, 1.0)";
        }
      ];
      input-field = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 3;
          placeholder_text = "Password or fingerprint";
        }
      ];
    };
  };

  services.blueman-applet.enable = true;
  services.mako.enable = true;
  # Notifications always target the built-in display, with the bar's colors
  # and font. mako keeps notifications forever by default, so they time out
  # after 10 s, like dunst did. Critical ones stay.
  services.mako.settings = {
    output = lib.mkDefault "eDP-1";
    font = "Roboto Condensed 11";
    background-color = "#2b303be6";
    text-color = "#ffffff";
    border-color = "#64727d";
    border-size = 2;
    border-radius = 0;
    padding = "10";
    margin = "10";
    width = 350;
    max-icon-size = 48;
    default-timeout = 10000;
    "urgency=critical" = {
      border-color = "#f53c3c";
      default-timeout = 0;
    };
  };

  services.hyprpolkitagent.enable = true;

  # Workaround: hyprpolkitagent has crashed on an AMD iGPU because Qt6
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

  # Wayland clipboard access for scripts and for anything that shells out to
  # wl-copy or wl-paste.
  home.packages = [ pkgs.wl-clipboard ];

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
      addons = [ (pkgs.callPackage ../../../packages/mac-unicode-hex { }) ];
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

  customScripts.stay-awake.enable = true;
  customScripts.toggle-sunset.enable = true;
  customScripts.toggle-sunset.asDesktopItem = true;
  customScripts.bluetooth-fix.enable = true;
  customScripts.bluetooth-fix.asDesktopItem = true;
  customScripts.audio-output.enable = true;
  customScripts.sx-lock.enable = true;
  customScripts.sx-lock.asDesktopItem = true;
  customScripts.sx-suspend.enable = true;
  customScripts.sx-suspend.asDesktopItem = true;
  customScripts.sx-hibernate.enable = true;
  customScripts.sx-hibernate.asDesktopItem = true;
}
