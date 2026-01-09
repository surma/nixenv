{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.waybar = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.waybar.enable) {
    home.packages = with pkgs; [ pavucontrol ];
    programs.waybar = {
      settings.mainBar = lib.readFile ./config |> builtins.fromJSON;
      style = lib.readFile ./style.css;
    };
  };
}
