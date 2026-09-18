{ lib, ... }:
# The user half of profiles/nixos/platform/framework.nix. Only the keyboard
# backlight lives here: the `framework_laptop::kbd_backlight` device exists on Framework
# laptops and nowhere else.
{
  # mkAfter keeps these binds behind the shared session config from
  # ../gui/hyprland.nix, so the generated Lua file stays stable.
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%+"), { locked = true, repeating = true })
    hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d framework_laptop::kbd_backlight set 5%-"), { locked = true, repeating = true })
  '';
}
