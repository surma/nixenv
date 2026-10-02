{
  pkgs,
  config,
  lib,
  inputs,
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
      "on-click" = "PATH=${
        lib.makeBinPath [
          sunsetScript
          pkgs.hyprland
          pkgs.systemd
        ]
      } toggle-sunset";
    };
  };
  niriEnabled = config.defaultConfigs.niri.enable;
  waybarConfigWithoutSunset =
    if sunsetScript == null then
      builtins.removeAttrs waybarConfig [ "custom/sunset" ]
      // {
        "modules-right" = lib.filter (module: module != "custom/sunset") waybarConfig."modules-right";
      }
    else
      waybarConfig;
  niriWorkspaceConfig = builtins.removeAttrs waybarConfig."hyprland/workspaces" [ "on-click" ] // {
    # The pinned niri module scrolls down/up with FocusWorkspaceDown/Up.
    "enable-bar-scroll" = true;
  };
  niriWaybarConfig = builtins.removeAttrs waybarConfigWithoutSunset [ "hyprland/workspaces" ] // {
    "modules-left" = [ "niri/workspaces" ];
    "niri/workspaces" = niriWorkspaceConfig;
  };
  stayAwakeEnabled = lib.attrByPath [ "customScripts" "stay-awake" "enable" ] false config;
  stayAwakeScript =
    if stayAwakeEnabled then
      lib.attrByPath [ "customScripts" "stay-awake" "package" ] null config
    else
      null;
  stayAwakePath = lib.makeBinPath [
    stayAwakeScript
    pkgs.procps
    pkgs.systemd
  ];
  stayAwakeConfig = lib.optionalAttrs (stayAwakeScript != null) {
    "custom/stay-awake" = waybarConfig."custom/stay-awake" // {
      "exec" = "PATH=${stayAwakePath} stay-awake status";
      "on-click" = "PATH=${stayAwakePath} stay-awake toggle";
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
      package = inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.waybar;
      settings.mainBar =
        (if niriEnabled then niriWaybarConfig else waybarConfigWithoutSunset)
        // sunsetConfig
        // stayAwakeConfig
        // {
          # The systemd unit has a restricted PATH, so pin the click command.
          "pulseaudio" = waybarConfig."pulseaudio" // {
            "on-click" = lib.getExe pkgs.pavucontrol;
          };
        }
        // lib.optionalAttrs (!niriEnabled) {
          # Hyprland with a Lua config only accepts Lua dispatch expressions.
          "hyprland/workspaces" = waybarConfig."hyprland/workspaces" // {
            "on-scroll-down" =
              "${lib.getExe' pkgs.hyprland "hyprctl"} dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'";
            "on-scroll-up" =
              "${lib.getExe' pkgs.hyprland "hyprctl"} dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'";
          };
        };
      style = lib.readFile ./style.css;
    };
  };
}
