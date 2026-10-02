{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  cfg = config.programs.handy;
in
{
  imports = [
    ../../home-manager/handy/default-config.nix
  ];

  options = {
    programs.handy = {
      enable = mkEnableOption "Handy speech-to-text tool";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.handy;
        description = "The handy package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];

    # Start Handy with the Wayland session. --start-hidden keeps it in the
    # tray instead of opening the main window on every login.
    systemd.user.services.handy = mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Handy speech-to-text";
        PartOf = [ config.wayland.systemd.target ];
        After = [ config.wayland.systemd.target ];
      };
      Install = {
        WantedBy = [ config.wayland.systemd.target ];
      };
      Service = {
        ExecStart = "${getExe cfg.package} --start-hidden";
      };
    };
  };
}
