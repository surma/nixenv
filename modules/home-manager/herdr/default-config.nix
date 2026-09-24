{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
with lib;
{
  options = {
    defaultConfigs.herdr = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.herdr.enable) {
    programs.herdr.settings = {
      onboarding = false;
      theme = {
        name = "gruvbox";
        auto_switch = false;
      };
      ui = {
        status_indicators = "symbols";
        sound.enabled = false;
        toast.delivery = "system";
      };
      terminal.default_shell = "${pkgs-unstable.nushell}/bin/nu";
      keys = {
        prefix = "ctrl+p";
        previous_workspace = "alt+left";
        next_workspace = "alt+right";
        previous_tab = "ctrl+shift+tab";
        next_tab = "ctrl+tab";
        detach = "prefix+q";
        new_tab = "prefix+t";
        rename_tab = "prefix+shift+t";
        new_workspace = "prefix+n";
        rename_workspace = "prefix+shift+n";
        help = "prefix+?";
        settings = "prefix+,";
        new_worktree = "";
        open_worktree = "";
        remove_worktree = "";
        close_workspace = "";
        workspace_picker = "";
        goto = "";
        navigate_workspace_up = "";
        navigate_workspace_down = "";
        navigate_pane_left = "";
        navigate_pane_down = "";
        navigate_pane_up = "";
        navigate_pane_right = "";
        reload_config = "prefix+;";
        open_notification_target = "";
        previous_agent = "";
        next_agent = "";
        focus_agent = "";
        remote_image_paste = "";
        move_tab_previous = "";
        move_tab_next = "";
        switch_tab = "";
        switch_workspace = "";
        close_tab = "prefix+shift+x";
        rename_pane = "";
        edit_scrollback = "";
        copy_mode = "";
        focus_pane_left = "prefix+left";
        focus_pane_down = "";
        focus_pane_up = "";
        focus_pane_right = "prefix+right";
        swap_pane_left = "";
        swap_pane_down = "";
        swap_pane_up = "";
        swap_pane_right = "";
        cycle_pane_next = "";
        cycle_pane_previous = "";
        last_pane = "";
        split_vertical = "prefix+r";
        split_horizontal = "";
        close_pane = "prefix+x";
        zoom = "";
        resize_mode = "";
        resize_pane_left = "";
        resize_pane_down = "";
        resize_pane_up = "";
        resize_pane_right = "";
        toggle_sidebar = "";
      };
    };
  };
}
