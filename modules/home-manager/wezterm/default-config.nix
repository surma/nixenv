{
  config,
  lib,
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
        in

        ''
          local light_scheme = ${builtins.toJSON wezterm.light-theme}
          local dark_scheme = ${builtins.toJSON wezterm.dark-theme}

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
                ''return ${builtins.toJSON wezterm.${"${wezterm.theme}-theme"}}''
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

          local config = wezterm.config_builder()
          config.front_end = "${wezterm.frontend}"
          config.send_composed_key_when_left_alt_is_pressed = true
          config.enable_tab_bar = false
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
          }


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
              key = '0',
              mods = 'CTRL',
              action = wezterm.action.DisableDefaultAssignment,
            },
            {
              key = 'r',
              mods = 'CTRL|SHIFT',
              action = wezterm.action.ReloadConfiguration,
            },
          }

          return config
        '';
    };
  };
}
