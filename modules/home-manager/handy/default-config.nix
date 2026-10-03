{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.handy = {
      enable = mkEnableOption "default Handy configuration";
    };
  };

  config = mkIf (config.defaultConfigs.handy.enable) {
    programs.handy.enable = true;

    # Handy registers its own shortcuts through X11, so they only fire while an
    # XWayland window has focus. Let Hyprland own the key and forward it to
    # the running instance instead.
    wayland.windowManager.hyprland.extraConfig = mkIf config.wayland.windowManager.hyprland.enable (mkAfter ''
      hl.bind("SUPER + ALT + space", hl.dsp.exec_cmd("${getExe config.programs.handy.package} --toggle-transcription"))
    '');

    defaultConfigs.sxwm.extraConfig = mkIf config.defaultConfigs.sxwm.enable (mkAfter ''
      wm.bind("Super+Alt+space", () => spawn("${getExe config.programs.handy.package} --toggle-transcription"));
    '');

    defaultConfigs.niri.binds = mkIf config.defaultConfigs.niri.enable (mkAfter ''
      Super+Alt+Space { spawn-sh "${getExe config.programs.handy.package} --toggle-transcription"; }
    '');
  };
}
