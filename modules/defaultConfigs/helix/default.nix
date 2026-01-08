{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.helix.enable = mkEnableOption "default helix configuration";

  config = mkIf config.defaultConfigs.helix.enable {
    programs.helix = import ./config.nix;
  };
}
