{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  bindingFlags = types.submodule {
    options = {
      l = mkOption {
        description = "locked, will also work when an input inhibitor (e.g. a lockscreen) is active.";
        type = types.bool;
        default = false;
      };
      r = mkOption {
        description = "release, will trigger on release of a key.";
        type = types.bool;
        default = false;
      };
      c = mkOption {
        description = "click, will trigger on release of a key or button as long as the mouse cursor stays inside binds:drag_threshold.";
        type = types.bool;
        default = false;
      };
      g = mkOption {
        description = "drag, will trigger on release of a key or button as long as the mouse cursor moves outside binds:drag_threshold.";
        type = types.bool;
        default = false;
      };
      o = mkOption {
        description = "longPress, will trigger on long press of a key.";
        type = types.bool;
        default = false;
      };
      e = mkOption {
        description = "repeat, will repeat when held.";
        type = types.bool;
        default = false;
      };
      n = mkOption {
        description = "non-consuming, key/mouse events will be passed to the active window in addition to triggering the dispatcher.";
        type = types.bool;
        default = false;
      };
      m = mkOption {
        description = "mouse, see below.";
        type = types.bool;
        default = false;
      };
      t = mkOption {
        description = "transparent, cannot be shadowed by other binds.";
        type = types.bool;
        default = false;
      };
      i = mkOption {
        description = "ignore mods, will ignore modifiers.";
        type = types.bool;
        default = false;
      };
      s = mkOption {
        description = "separate, will arbitrarily combine keys between each mod/key, see [Keysym combos](#keysym-combos) above.";
        type = types.bool;
        default = false;
      };
      d = mkOption {
        description = "has description, will allow you to write a description for your bind.";
        type = types.bool;
        default = false;
      };
      p = mkOption {
        description = "bypasses the app's requests to inhibit keybinds.";
        type = types.bool;
        default = false;
      };
    };
  };
  actionType = types.submodule {
    options = {
      activateWorkspace = mkOption {
        type = types.nullOr (
          types.oneOf [
            types.int
            types.str
          ]
        );
        default = null;
        description = "Workspace number or name to activate";
      };
      moveToWorkspace = mkOption {
        type = types.nullOr (
          types.oneOf [
            types.int
            types.str
          ]
        );
        default = null;
        description = "Workspace number or name to move window to";
      };
      moveFocus = mkOption {
        type = types.nullOr (
          types.enum [
            "l"
            "r"
            "u"
            "d"
          ]
        );
        default = null;
        description = "Direction to move focus";
      };
      layoutMsg = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Layout message to send";
      };
      toggleFloating = mkOption {
        type = types.nullOr types.anything;
        default = null;
        description = "Layout message to send";
      };
      exec = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Command to execute";
      };
      text = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Raw string";
      };
    };
  };

  binding = {
    options = {
      key = mkOption {
        type = types.str;
        description = "Key combination (e.g., '$mainMod SHIFT, W')";
      };
      flags = mkOption {
        type = types.nullOr bindingFlags;
        description = "Flags for the binding";
        default = null;
      };
      action = mkOption {
        type = actionType;
        description = "Action to perform";
      };
    };
  };
in
{
  imports = [
    ./default-config.nix
  ];

  options = {
    wayland.windowManager.hyprland = {
      bindings = mkOption {
        type = with types; listOf (submodule binding);
        default = [ ];
        description = "Structured keybindings with type checking";
      };
      header = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };
  config =
    let
      inherit (config.wayland.windowManager) hyprland;

      asBindingKeyword =
        bind:
        "bind"
        + (
          if bind == null then
            ""
          else
            bind
            |> lib.attrsToList
            |> lib.filter ({ value, ... }: value)
            |> lib.map ({ name, ... }: name)
            |> lib.concatStrings
        );

      actionToCommand =
        action:
        let
          actionToCommandMap = {
            text = a: a.text;
            activateWorkspace = a: "workspace, ${toString a.activateWorkspace}";
            moveToWorkspace = a: "movetoworkspace, ${toString a.moveToWorkspace}";
            moveFocus = a: "movefocus, ${a.moveFocus}";
            layoutMsg = a: "layoutmsg, ${a.layoutMsg}";
            exec = a: "exec, ${a.exec}";
            toggleFloating = a: "togglefloating";
          };

          propName =
            action
            |> lib.attrsToList
            |> lib.filter ({ value, ... }: value != null)
            |> lib.map ({ name, value }: name)
            |> (l: throwIf ((l |> lib.length) == 0) "Action missing ${l |> builtins.toJSON}" l)
            |> (l: throwIf ((l |> lib.length) > 1) "Action has multiple actions defined" l)
            |> (l: lib.elemAt l 0);
        in
        actionToCommandMap.${propName} action;

      bindings =
        hyprland.bindings
        |> map (
          binding: "${binding.flags |> asBindingKeyword} = ${binding.key}, ${actionToCommand binding.action}"
        )
        |> lib.concatLines;
    in

    {
      wayland.windowManager.hyprland = {
        extraConfig = ''
          ${hyprland.header}
          ${bindings}
          ${lib.readFile ./hyprland.conf}
        '';
      };
    };
}
