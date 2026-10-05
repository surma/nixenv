{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  sxwm = inputs.sxwm.packages.${pkgs.stdenv.hostPlatform.system}.sxwm;
  sxwmctl = "${sxwm}/bin/sxwmctl";
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 32;
  windowSwitcher = pkgs.writeShellApplication {
    name = "sxwm-window-switcher";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.jq
      sxwm
    ];
    text = lib.readFile ./window-switcher.sh;
  };
  sxwmConfig = pkgs.writeText "sxwm-config.js" (
    builtins.replaceStrings
      [
        "@fuzzel@"
        "@window-switcher@"
        "@cursor-theme@"
        "@cursor-size@"
        "@extraConfig@"
      ]
      [
        "${pkgs.fuzzel}/bin/fuzzel"
        (lib.getExe windowSwitcher)
        cursorTheme
        (toString cursorSize)
        config.defaultConfigs.sxwm.extraConfig
      ]
      (lib.readFile ./config.js)
  );
  # SXWM falls back to its default configuration when this file fails, so
  # catch syntax errors at build time.
  validatedConfig =
    pkgs.runCommand "sxwm-config-validated.js"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
      }
      ''
        cp ${sxwmConfig} config.mjs
        node --check config.mjs
        cp ${sxwmConfig} "$out"
      '';
  powerOn = "${sxwmctl} outputs.power '{\"on\": true}'";
  powerOff = "${sxwmctl} outputs.power '{\"on\": false}'";
in
{
  options.defaultConfigs.sxwm = {
    enable = lib.mkEnableOption "";
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional JavaScript at the end of the SXWM configuration.";
    };
  };

  config = lib.mkIf config.defaultConfigs.sxwm.enable {
    home.pointerCursor = {
      package = pkgs.bibata-cursors;
      name = cursorTheme;
      size = cursorSize;
      gtk.enable = true;
    };

    # niri's environment block, for the user services of the session.
    systemd.user.sessionVariables = {
      QT_QPA_PLATFORM = "wayland";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      GDK_BACKEND = "wayland";
    };

    xdg.configFile."sxwm/config.js".source = validatedConfig;

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
      # See the same setting in ../niri/default-config.nix.
      package = pkgs-unstable.hypridle;
      systemdTarget = config.wayland.systemd.target;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = powerOn;
        };

        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = powerOff;
            on-resume = powerOn;
          }
        ];
      };
    };
  };
}
