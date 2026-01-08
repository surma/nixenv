{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.zsh.enable = mkEnableOption "default zsh configuration";

  config = mkIf config.defaultConfigs.zsh.enable {
    programs.zsh = (import ./config.nix { inherit lib; }).config;
  };
}
