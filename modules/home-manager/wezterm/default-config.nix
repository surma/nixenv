{
  config,
  lib,
  inputs,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.wezterm = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.wezterm.enable) {
    programs.wezterm = {
      extraConfig =
        let
          inherit (config.programs) wezterm;
          palette = import ../../../lib/sx-palette.nix { inherit inputs; };
          lua = builtins.toJSON;
          luaArray = values: "{ ${lib.concatStringsSep ", " (map lua values)} }";
        in

        ''
          local light_scheme = ${builtins.toJSON wezterm.light-theme}
          local dark_scheme = ${builtins.toJSON wezterm.dark-theme}
          local sx_schemes = {
            ['SX Dark'] = {
              foreground = ${lua palette.bone},
              background = ${lua palette.carbon},
              cursor_bg = ${lua palette.steel},
              cursor_fg = ${lua palette.carbon},
              cursor_border = ${lua palette.steel},
              selection_bg = ${lua palette.gunmetal},
              selection_fg = ${lua palette.bone},
              split = ${lua palette.graphite},
              scrollbar_thumb = ${lua palette.steel},
              ansi = ${luaArray [
                palette.gunmetal
                palette.halt
                palette.go
                palette.caution
                palette.blue
                palette.magenta
                palette.cyan
                palette.concrete
              ]},
              brights = ${luaArray [
                palette.steel
                palette."halt-bright"
                palette."go-bright"
                palette."caution-bright"
                palette."blue-bright"
                palette."magenta-bright"
                palette."cyan-bright"
                palette.bone
              ]},
              tab_bar = {
                background = ${lua palette.gunmetal},
                inactive_tab_edge = ${lua palette.graphite},
                active_tab = { bg_color = ${lua palette.carbon}, fg_color = ${lua palette.bone}, intensity = 'Bold' },
                inactive_tab = { bg_color = ${lua palette.carbon}, fg_color = ${lua palette.steel} },
                inactive_tab_hover = { bg_color = ${lua palette.graphite}, fg_color = ${lua palette.bone} },
                new_tab = { bg_color = ${lua palette.gunmetal}, fg_color = ${lua palette.bone} },
                new_tab_hover = { bg_color = ${lua palette.concrete}, fg_color = ${lua palette.carbon} },
              },
            },
            ['SX Light'] = {
              foreground = ${lua palette.carbon},
              background = ${lua palette.bone},
              cursor_bg = ${lua palette.graphite},
              cursor_fg = ${lua palette.bone},
              cursor_border = ${lua palette.graphite},
              selection_bg = ${lua palette.concrete},
              selection_fg = ${lua palette.carbon},
              split = ${lua palette.concrete},
              scrollbar_thumb = ${lua palette.graphite},
              ansi = ${luaArray [
                palette.carbon
                palette."halt-deep"
                palette."go-deep"
                palette."caution-deep"
                palette."blue-deep"
                palette."magenta-deep"
                palette."cyan-deep"
                palette.concrete
              ]},
              brights = ${luaArray [
                palette.graphite
                palette."halt-deep-bright"
                palette."go-deep-bright"
                palette."caution-deep-bright"
                palette."blue-deep-bright"
                palette."magenta-deep-bright"
                palette."cyan-deep-bright"
                palette.bone
              ]},
              tab_bar = {
                background = ${lua palette.bone},
                inactive_tab_edge = ${lua palette.concrete},
                active_tab = { bg_color = ${lua palette.concrete}, fg_color = ${lua palette.carbon}, intensity = 'Bold' },
                inactive_tab = { bg_color = ${lua palette.bone}, fg_color = ${lua palette.graphite} },
                inactive_tab_hover = { bg_color = ${lua palette.concrete}, fg_color = ${lua palette.carbon} },
                new_tab = { bg_color = ${lua palette.bone}, fg_color = ${lua palette.graphite} },
                new_tab_hover = { bg_color = ${lua palette.gunmetal}, fg_color = ${lua palette.bone} },
              },
            },
          }

          function scheme_for_appearance(appearance)
            ${
              if wezterm.theme == "auto" then
                ''
                  if appearance:find 'Dark' then
                    return dark_scheme
                  else
                    return light_scheme
                  end
                ''
              else
                "return ${builtins.toJSON wezterm.${"${wezterm.theme}-theme"}}"
            }
          end

          wezterm.on('window-config-reloaded', function(window, pane)
            local overrides = window:get_config_overrides() or {}
            local appearance = window:get_appearance()
            local scheme = scheme_for_appearance(appearance)
            if overrides.color_scheme ~= scheme then
              overrides.color_scheme = scheme
              window:set_config_overrides(overrides)
            end
          end)

          local is_macos = wezterm.target_triple:find('darwin') ~= nil
          local copy_to_clipboard = wezterm.action.CopyTo 'ClipboardAndPrimarySelection'
          local paste_from_clipboard = wezterm.action.PasteFrom 'Clipboard'
          local linux_ctrl_c = wezterm.action_callback(function(window, pane)
            local selection = window:get_selection_text_for_pane(pane)
            if selection ~= "" then
              window:perform_action(copy_to_clipboard, pane)
              window:perform_action(wezterm.action.ClearSelection, pane)
            else
              window:perform_action(
                wezterm.action.SendKey { key = 'c', mods = 'CTRL' },
                pane
              )
            end
          end)

          local config = wezterm.config_builder()
          config.front_end = "${wezterm.frontend}"
          config.color_schemes = sx_schemes
          config.enable_kitty_keyboard = true
          config.default_cursor_style = 'SteadyBlock'
          config.animation_fps = 1
          config.max_fps = 30
          config.window_background_opacity = 0.95
          -- SXWM does not implement ext-background-effect-v1 yet, so blur has no effect there.
          config.wayland_window_background_blur = true
          config.macos_window_background_blur = 0
          config.send_composed_key_when_left_alt_is_pressed = true
          config.enable_tab_bar = false
          -- One line per wheel event in full-screen TUIs. The default of 3
          -- makes a high-resolution touchpad scroll far too fast in pi,
          -- herdr and pagers, while GUI apps that handle smooth scrolling
          -- themselves are unaffected.
          config.alternate_buffer_wheel_scroll_speed = 1
          config.window_padding = {
            top = "0.5cell",
            bottom = "0.5cell",
            left = "0.5cell",
            right = "0.5cell",
          }
          config.color_scheme = dark_scheme
          config.font = wezterm.font 'Fira Code'
          config.font_size = ${toString wezterm.fontSize}
          config.window_decorations = '${
            if wezterm.window-decorations == null then
              "NONE"
            else
              lib.concatStringsSep "|" wezterm.window-decorations
          }'
          config.window_frame = {
            font = wezterm.font({ family = 'Fira Code', weight = 'Bold' }),
            font_size = 11,
            active_titlebar_bg = ${lua palette.gunmetal},
            active_titlebar_fg = ${lua palette.bone},
            inactive_titlebar_bg = ${lua palette.carbon},
            inactive_titlebar_fg = ${lua palette.steel},
            button_bg = ${lua palette.gunmetal},
            button_fg = ${lua palette.bone},
            button_hover_bg = ${lua palette.concrete},
            button_hover_fg = ${lua palette.carbon},
          }

          config.disable_default_key_bindings = true
          config.keys = {
            {
              key = '-',
              mods = 'CTRL',
              action = wezterm.action.DisableDefaultAssignment,
            },
            {
              key = '=',
              mods = 'CTRL',
              action = wezterm.action.DisableDefaultAssignment,
            },
            {
              key = '-',
              mods = 'CMD',
              action = wezterm.action.DecreaseFontSize,
            },
            {
              key = '=',
              mods = 'CMD',
              action = wezterm.action.IncreaseFontSize,
            },
            {
              key = '0',
              mods = is_macos and 'CMD' or 'CTRL',
              action = wezterm.action.ResetFontSize,
            },
            {
              key = 'r',
              mods = 'CTRL|SHIFT',
              action = wezterm.action.ReloadConfiguration,
            },
            {
              key = 'n',
              mods = is_macos and 'CMD' or 'CTRL',
              action = wezterm.action.SpawnWindow,
            },
            {
              key = 'c',
              mods = is_macos and 'CMD' or 'CTRL',
              action = is_macos and copy_to_clipboard or linux_ctrl_c,
            },
            {
              key = 'v',
              mods = is_macos and 'CMD' or 'CTRL',
              action = paste_from_clipboard,
            },
          }

          return config
        '';
    };
  };
}
