{
  config,
  lib,
  ...
}:
with lib;
{
  options.defaultConfigs.surma-noti = {
    enable = mkEnableOption "";
  };

  config = mkIf config.defaultConfigs.surma-noti.enable {
    programs.surma-noti.enable = true;
    programs.surma-noti.defaultMobileDevice = mkDefault "surmpixel";
  };
}
