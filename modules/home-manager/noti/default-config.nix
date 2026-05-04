{
  config,
  lib,
  ...
}:
with lib;
{
  options.defaultConfigs.noti = {
    enable = mkEnableOption "";
  };

  config = mkIf config.defaultConfigs.noti.enable {
    programs.noti.enable = true;
    programs.noti.defaultMobileDevice = mkDefault "surmpixel";
  };
}
