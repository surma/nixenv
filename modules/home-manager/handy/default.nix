{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.programs.handy;
in
{
  imports = [
    ./default-config.nix
  ];

  options = {
    programs.handy = {
      enable = mkEnableOption "Handy speech-to-text tool";
      package = mkOption {
        type = types.package;
        default = pkgs.handy;
        description = "The handy package to use";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
