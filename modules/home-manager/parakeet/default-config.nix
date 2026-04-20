{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    defaultConfigs.parakeet = {
      enable = mkEnableOption "default Parakeet configuration";
    };
  };

  config = mkIf (config.defaultConfigs.parakeet.enable) {
    programs.parakeet.enable = true;
  };
}
