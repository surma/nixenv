{
  pkgs,
  config,
  lib,
  ...
}:
let
  disabledWorkspaces = "QWF" |> lib.stringToCharacters;
  numberWorkspaces =
    "123456789"
    |> lib.stringToCharacters
    |> lib.imap (
      i: key: {
        inherit key;
        idx = i - 1;
      }
    );

  letterWorkspaces =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    |> lib.stringToCharacters
    |> lib.imap (
      i: key: {
        inherit key;
        idx = i + 9;
      }
    );

  workspaceBindings =
    (numberWorkspaces ++ letterWorkspaces)
    |> lib.filter ({ key, ... }: !lib.elem key disabledWorkspaces)
    |> lib.map (
      { idx, key }:
      [
        {
          key = "$meh, ${key}";
          action.activateWorkspace = idx;
        }
        {
          key = "$meh SHIFT, ${key}";
          action.moveToWorkspace = idx;
        }
      ]
    )
    |> lib.flatten;

in
with lib;
{
  options = {
    defaultConfigs.hyprland = {
      enable = mkEnableOption "";
    };
  };
  config = {
    wayland.windowManager.hyprland = mkIf (config.defaultConfigs.hyprland.enable) {
      header = ''
        $meh = SUPER ALT CTRL
      '';
      bindings = workspaceBindings ++ [
        {
          key = "$meh SHIFT, W";
          action.text = "killactive";
        }
        {
          key = "$meh SHIFT, Q";
          action.text = "exit";
        }
        {
          key = "$meh, left";
          action.moveFocus = "l";
        }
        {
          key = "$meh, right";
          action.moveFocus = "r";
        }
        {
          key = "$meh, up";
          action.moveFocus = "u";
        }
        {
          key = "$meh, down";
          action.moveFocus = "d";
        }
        {
          key = "$meh, return";
          action.layoutMsg = "swapwithmaster";
        }
        {
          key = "$meh, minus";
          action.layoutMsg = "mfact -0.01";
        }
        {
          key = "$meh, equal";
          action.layoutMsg = "mfact +0.01";
        }
        {
          key = "$meh SHIFT, slash";
          action.toggleFloating = true;
        }
        {
          key = "$meh SHIFT, equal";
          action.text = "fullscreen";
        }
        {
          key = "$meh, grave";
          action.text = "togglespecialworkspace, magic";
        }
        {
          key = "$meh SHIFT, grave";
          action.moveToWorkspace = "special:magic";
        }
        {
          key = "SUPER, space";
          action.exec = "${pkgs.wofi}/bin/wofi --show drun";
        }
        {
          key = "$meh, period";
          action.text = "movecurrentworkspacetomonitor, d";
        }
        {
          key = "$meh, comma";
          action.text = "movecurrentworkspacetomonitor, u";
        }
        {
          key = ",XF86AudioRaiseVolume";
          action.exec = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86AudioLowerVolume";
          action.exec = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86AudioMute";
          action.exec = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86AudioMicMute";
          action.exec = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86MonBrightnessUp";
          action.exec = "brightnessctl -e4 -n2 set 5%+";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86MonBrightnessDown";
          action.exec = "brightnessctl -e4 -n2 set 5%-";
          flags.e = true;
          flags.l = true;
        }
        {
          key = ",XF86AudioNext";
          action.exec = "playerctl next";
          flags.l = true;
        }
        {
          key = ",XF86AudioPause";
          action.exec = "playerctl play-pause";
          flags.l = true;
        }
        {
          key = ",XF86AudioPlay";
          action.exec = "playerctl play-pause";
          flags.l = true;
        }
        {
          key = ",XF86AudioPrev";
          action.exec = "playerctl previous";
          flags.l = true;
        }
        {
          key = "$meh, mouse:272";
          action.text = "movewindow";
          flags.m = true;
        }
        {
          key = "$meh SHIFT, mouse:272";
          action.text = "resizewindow";
          flags.m = true;
        }
      ];
    };
  };
}
