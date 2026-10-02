{ config, lib, ... }:
# The user half of profiles/nixos/platform/framework.nix. Only the keyboard
# backlight lives here: the `framework_laptop::kbd_backlight` device exists on Framework
# laptops and nowhere else.
{
  # mkAfter appends these binds after the shared Hyprland input config, so the
  # generated Lua file stays stable.
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%+"), { locked = true, repeating = true })
    hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%-"), { locked = true, repeating = true })
  '';

  defaultConfigs.niri.binds = lib.mkIf config.defaultConfigs.niri.enable (
    lib.mkAfter ''
      Shift+XF86MonBrightnessUp allow-when-locked=true { spawn-sh "brightnessctl -d framework_laptop::kbd_backlight set 5%+"; }
      Shift+XF86MonBrightnessDown allow-when-locked=true { spawn-sh "brightnessctl -d framework_laptop::kbd_backlight set 5%-"; }
    ''
  );
}
