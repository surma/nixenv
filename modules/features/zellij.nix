{
  config,
  pkgs,
  lib,
  inputs,
  systemManager,
  ...
}:
let
  inherit (pkgs) wl-clipboard;
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
in
with lib;
{
  # Zellij is home-manager only, no system-level config needed
  options = {
    programs.zellij.wl-clipboard.enable = mkEnableOption "Use wl-clipboard";
  };

  config = mkIf (systemManager == "home-manager") {
    programs.zellij = {
      enable = true;
      package = pkgs-unstable.zellij;
      settings = {
        pane_frames = false;
        session_serialization = false;
        show_startup_tips = false;
        default_shell = "${pkgs-unstable.nushell}/bin/nu";

        copy_command = mkIf config.programs.zellij.wl-clipboard.enable "${wl-clipboard}/bin/wl-copy -p";
        theme = "gruvbox";
        themes = {
          gruvbox = {
            fg = "#D5C4A1";
            bg = "#282828";
            black = "#3C3836";
            red = "#CC241D";
            green = "#98971A";
            yellow = "#D79921";
            blue = "#3C8588";
            magenta = "#B16286";
            cyan = "#689D6A";
            white = "#FBF1C7";
            orange = "#D65D0E";
          };
        };

        keybinds = {
          "shared_except \"locked\"" = {
            unbind = [
              "Ctrl q"
              "Ctrl g"
            ];
            "bind \"Ctrl y\"" = {
              SwitchToMode = "Locked";
            };
          };
          locked = {
            unbind = [
              "Ctrl g"
            ];
            "bind \"Ctrl y\"" = {
              SwitchToMode = "Normal";
            };
          };
        };
      };
    };
  };
}
