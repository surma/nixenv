{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.defaultConfigs.helix;
in
{
  options.defaultConfigs.helix = {
    enable = mkEnableOption "default helix configuration";
  };

  config = mkIf cfg.enable {
    programs.helix = import ./config.nix { };
  };
}
