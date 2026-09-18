{ config, lib, ... }:
let
  apps = {
    squoosh = {
      url = "https://squoosh.app";
      title = "Squoosh";
    };
    xbox-remote-play = {
      url = "https://xbox.com/play/consoles";
      title = "XBox Remote Play";
    };
    geforce-now = {
      url = "https://play.geforcenow.com/games";
      title = "GeForce NOW";
    };
  };
in
with lib;
{
  imports = [
    ../../../modules/home-manager/webapp-wrapper
  ];
  options = {
    programs = apps |> lib.mapAttrs (name: value: { enable = mkEnableOption value.title; });
  };
  config.programs.webapps.apps =
    apps |> lib.mapAttrs (name: value: mkIf (config.programs.${name}.enable) value);
}
