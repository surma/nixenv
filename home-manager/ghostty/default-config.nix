{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.ghostty = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.ghostty.enable) {
    programs.ghostty = {
      clearDefaultKeybinds = true;
      settings = {
        theme = "light:Gruvbox Light,dark:Gruvbox Dark";

        font-family = "Fira Code";
        font-size = 12;

        gtk-tabs-location = "hidden";

        keybind = [
          "super+alt+i=inspector:toggle"
          "super+shift+p=toggle_command_palette"
          "super+equal=increase_font_size:1"
          "super+-=decrease_font_size:1"
          "super+0=reset_font_size"
          "super+f=start_search"
          "super+n=new_window"
          "super+q=quit"
          "super+c=copy_to_clipboard:mixed"
          "super+v=paste_from_clipboard"
          "copy=copy_to_clipboard:mixed"
          "paste=paste_from_clipboard"
        ];
      };
    };
  };

}
