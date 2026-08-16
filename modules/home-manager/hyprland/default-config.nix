{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.defaultConfigs.hyprland.enable = lib.mkEnableOption "";

  config = lib.mkIf config.defaultConfigs.hyprland.enable {
    wayland.windowManager.hyprland = {
      configType = "lua";
      # The Lua config keeps commands unpinned (resolved via PATH) except the
      # launcher, which is pinned to the exact wofi store path via @wofi@.
      extraConfig = builtins.replaceStrings [ "@wofi@" ] [ "${pkgs.wofi}/bin/wofi" ] (
        lib.readFile ./hyprland.lua
      );
    };

    services.hypridle = {
      enable = true;
      # Start after Hyprland has imported its Wayland/systemd environment.
      systemdTarget = "hyprland-session.target";
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        };

        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
          }
        ];
      };
    };

    xdg.desktopEntries = {
      hyprlock = {
        name = "Hyprlock";
        exec = "${pkgs.hyprlock}/bin/hyprlock";
      };
      hypridle = {
        name = "Hypridle";
        exec = "${pkgs.systemd}/bin/systemctl --user start hypridle.service";
      };
    };

    # Home Manager normally uses `reload config-only`, which cannot replace a
    # running legacy config manager with the Lua config manager. Use Hyprland's
    # full reset only for that transition; ordinary Lua edits keep the lighter
    # config-only reload.
    xdg.configFile."hypr/hyprland.lua".onChange = lib.mkForce ''
      (
        XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
        if [[ -d "/tmp/hypr" || -d "$XDG_RUNTIME_DIR/hypr" ]]; then
          for instance in $(${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl instances -j | ${pkgs.jq}/bin/jq ".[].instance" -r); do
            if ${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl -i "$instance" systeminfo \
              | ${pkgs.gnugrep}/bin/grep -Fqx 'configProvider: lua'; then
              ${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl -i "$instance" reload config-only
            else
              ${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl -i "$instance" reload full-reset
            fi
          done
        fi
      )
    '';
  };
}
