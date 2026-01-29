{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.handy = {
      enable = mkEnableOption "default Handy configuration";
    };
  };

  config = mkIf (config.defaultConfigs.handy.enable) {
    programs.handy.enable = true;
  };
}
