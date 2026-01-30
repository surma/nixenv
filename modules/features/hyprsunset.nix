{ config, lib, pkgs, systemManager, ... }:
let
  inherit (config.programs) hyprsunset;
in
with lib;
{
  options = {
    programs.hyprsunset = {
      enable = mkEnableOption "hyprsunset";
      package = mkPackageOption pkgs "hyprsunset" { };
    };
  };

  config = mkIf (systemManager == "home-manager" && hyprsunset.enable) {
    home.packages = [ hyprsunset.package ];
    systemd.user.services.hyprsunset = {
      Unit = {
        Description = "Starts hyprsunset to control tint and gamma";
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
      Service = {
        ExecStart = "${hyprsunset.package}/bin/hyprsunset";
      };
    };
  };
}
