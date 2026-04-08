{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.karabiner.enable = mkEnableOption "default karabiner configuration";

  config = mkIf config.defaultConfigs.karabiner.enable {
    home.file.".config/karabiner/karabiner.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/src/github.com/surma/nixenv/modules/defaultConfigs/karabiner/config.json";
  };
}
