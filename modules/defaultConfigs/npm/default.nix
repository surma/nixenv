{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.npm.enable = mkEnableOption "default npm configuration";

  config = mkIf config.defaultConfigs.npm.enable {
    home.file.".npmrc" = {
      source = ./npmrc;
      mutable = true;
    };
  };
}
