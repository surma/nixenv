{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) hyprpaper;
in
with lib;
{
  imports = [
    ./default-config.nix
  ];
  options = {
    programs.hyprpaper = {
      enable = mkEnableOption "";
      package = mkPackageOption pkgs "hyprpaper" { };
    };
  };
  config = mkIf hyprpaper.enable {
    home.packages = [ hyprpaper.package ];
    systemd.user.services.hyprpaper = {
      Unit = {
        Description = "Starts hyprpaper to control tint and gamma";
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
