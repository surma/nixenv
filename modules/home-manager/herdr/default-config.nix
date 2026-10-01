{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Zellij-style cycle: step through every pane of the workspace, tab by tab,
  # and wrap around at the end. `pane list --workspace` already returns the
  # panes in tab order, then split order. `pane.focus` also switches the tab.
  # The CLI cannot focus a non-agent pane by id, so the script talks to the
  # socket directly.
  cyclePane = pkgs.writeShellScript "herdr-cycle-pane" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        config.programs.herdr.package
        pkgs.jq
        pkgs.socat
      ]
    }:$PATH

    step=1
    if [ "''${1:-next}" = prev ]; then step=-1; fi

    target="$(herdr pane list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" \
      | jq -r --arg cur "$HERDR_ACTIVE_PANE_ID" --argjson step "$step" '
          [.result.panes[].pane_id] as $ids
          | ($ids | index($cur)) as $i
          | if $i == null then empty
            else $ids[($i + $step + ($ids | length)) % ($ids | length)] end')"
    [ -n "$target" ] || exit 0

    jq -cn --arg id "$target" \
      '{id: "cycle-pane", method: "pane.focus", params: {pane_id: $id}}' \
      | socat - "UNIX-CONNECT:$HERDR_SOCKET_PATH" > /dev/null
  '';
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
        # ctrl+tab and ctrl+shift+tab belong to the pane cycle below.
        previous_tab = "";
        next_tab = "";
        command = [
          {
            key = "ctrl+tab";
            type = "shell";
            command = "${cyclePane} next";
            description = "next pane, then next tab";
          }
          {
            key = "ctrl+shift+tab";
            type = "shell";
            command = "${cyclePane} prev";
            description = "previous pane, then previous tab";
          }
        ];
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
