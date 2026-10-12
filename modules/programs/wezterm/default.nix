{ lib, systemManager, ... }:
with lib;
{
  imports = [
    ../../home-manager/wezterm/default-config.nix
  ];

  options.programs.wezterm = {
    frontend = mkOption {
      type =
        with types;
        enum [
          "WebGpu"
          "OpenGL"
        ];
      default = "WebGpu";
    };
    fontSize = mkOption {
      type = types.int;
      default = 12;
    };
    window-decorations = mkOption {
      type =
        with types;
        nullOr (
          listOf (enum [
            "RESIZE"
            "TITLE"
          ])
        );
      default = [
        "TITLE"
        "RESIZE"
      ];
    };
    dark-theme = mkOption {
      type = types.str;
      default = "SX Dark";
    };
    light-theme = mkOption {
      type = types.str;
      default = "SX Light";
    };
    theme = mkOption {
      type =
        with types;
        enum [
          "dark"
          "light"
          "auto"
        ];
      default = "auto";
    };
  };
}
