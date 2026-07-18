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
