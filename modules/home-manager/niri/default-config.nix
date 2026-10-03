{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 32;
  windowSwitcher = pkgs.writeShellApplication {
    name = "niri-window-switcher";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.jq
      pkgs.niri
    ];
    text = lib.readFile ./window-switcher.sh;
  };
  niriConfig = pkgs.writeText "niri-config.kdl" (
    builtins.replaceStrings
      [
        "@fuzzel@"
        "@window-switcher@"
        "@cursor-theme@"
        "@cursor-size@"
        "@binds@"
        "@extraConfig@"
      ]
      [
        "${pkgs.fuzzel}/bin/fuzzel"
        (lib.getExe windowSwitcher)
        cursorTheme
        (toString cursorSize)
        config.defaultConfigs.niri.binds
        config.defaultConfigs.niri.extraConfig
      ]
      (lib.readFile ./config.kdl)
  );
  validatedConfig =
    pkgs.runCommand "niri-config-validated.kdl"
      {
        nativeBuildInputs = [ pkgs.niri ];
      }
      ''
        niri validate -c ${niriConfig}
        cp ${niriConfig} "$out"
      '';
in
{
  options.defaultConfigs.niri = {
    enable = lib.mkEnableOption "";
    binds = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional lines inside the Niri binds block.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional top-level Niri config nodes.";
    };
  };

  config = lib.mkIf config.defaultConfigs.niri.enable {
    home.pointerCursor = {
      package = pkgs.bibata-cursors;
      name = cursorTheme;
      size = cursorSize;
      gtk.enable = true;
    };

    xdg.configFile."niri/config.kdl".source = validatedConfig;

    xdg.desktopEntries = {
      hyprlock = {
        name = "Hyprlock";
        exec = "${pkgs.hyprlock}/bin/hyprlock";
      };
      hypridle = {
        name = "Hypridle";
        exec = "${pkgs.systemd}/bin/systemctl --user start hypridle.service";
      };
    };

    services.hypridle = {
      enable = true;
      # hypridle 0.1.7 leaks an inhibit lock and then never locks the
      # screen. 0.1.8 fixes this.
      package = pkgs-unstable.hypridle;
      systemdTarget = config.wayland.systemd.target;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "niri msg action power-on-monitors";
        };

        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "niri msg action power-off-monitors";
            on-resume = "niri msg action power-on-monitors";
          }
        ];
      };
    };
  };
}
