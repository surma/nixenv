{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.aerospace.enable = mkEnableOption "default aerospace configuration";

  config = mkIf config.defaultConfigs.aerospace.enable {
    home.file.".config/aerospace/aerospace.toml".source = ./config.toml;
  };
}
