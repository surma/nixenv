{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  waybarConfig = builtins.fromJSON (lib.readFile ./config);
  sunsetEnabled = lib.attrByPath [ "customScripts" "toggle-sunset" "enable" ] false config;
  sunsetScript =
    if sunsetEnabled then
      lib.attrByPath [ "customScripts" "toggle-sunset" "package" ] null config
    else
      null;
  sunsetConfig = lib.optionalAttrs (sunsetScript != null) {
    "custom/sunset" = waybarConfig."custom/sunset" // {
      "on-click" =
        "PATH=${lib.makeBinPath [
          sunsetScript
          pkgs.hyprland
          pkgs.systemd
        ]} toggle-sunset";
    };
  };
in
{
  options = {
    defaultConfigs.waybar = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.waybar.enable) {
    home.packages = with pkgs; [ pavucontrol ];
    programs.waybar = {
      settings.mainBar =
        waybarConfig
        // sunsetConfig
        // {
          # The systemd unit has a restricted PATH, so pin the click command.
          "pulseaudio" = waybarConfig."pulseaudio" // {
            "on-click" = lib.getExe pkgs.pavucontrol;
          };
        };
      style = lib.readFile ./style.css;
    };
  };
}
