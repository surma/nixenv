{
  pkgs,
  config,
  lib,
  systemManager,
  ...
}:
with lib;
let
  cfg = config.programs.noti;
  notiPackage = pkgs.callPackage ../../../packages/noti {
    defaultMobileDevice =
      if cfg.defaultMobileDevice != null then cfg.defaultMobileDevice else null;
  };
in
{
  imports = [
    ../../home-manager/noti/default-config.nix
  ];

  options.programs.noti = {
    enable = mkEnableOption "noti notification CLI";
    package = mkOption {
      type = types.package;
      default = notiPackage;
      description = "The noti package to use";
    };
    defaultMobileDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default Home Assistant mobile device name for `noti mobile` (e.g. 'surmpixel')";
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];
  };
}
