{
  config,
  lib,
  pkgs,
  systemManager,
  ...
}:
let
  inherit (config.programs) hyprpaper;
in
with lib;
{
  imports = [
    ../home-manager/hyprpaper/default-config.nix
  ];

  options = {
    programs.hyprpaper = {
      enable = mkEnableOption "hyprpaper";
      package = mkPackageOption pkgs "hyprpaper" { };
    };
  };

  config = mkIf (systemManager == "home-manager" && hyprpaper.enable) {
    home.packages = [ hyprpaper.package ];
    systemd.user.services.hyprpaper = {
      Unit = {
        Description = "Starts hyprpaper wallpaper manager";
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
      Service = {
        ExecStart = "${hyprpaper.package}/bin/hyprpaper";
      };
    };
  };
}
