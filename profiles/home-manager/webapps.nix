{ config, lib, ... }:
let
  apps = {
    whatsapp = {
      url = "https://web.whatsapp.com";
      title = "WhatsApp";
    };
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
    ./webapp-wrapper.nix
  ];
  options = {
    programs = apps |> lib.mapAttrs (name: value: { enable = mkEnableOption value.title; });
  };
  config.programs.webapps.apps =
    apps |> lib.mapAttrs (name: value: mkIf (config.programs.${name}.enable) value);
}
