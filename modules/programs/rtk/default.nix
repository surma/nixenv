{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
{
  options = {
    programs.rtk = {
      enable = mkEnableOption "rtk (Rust Token Killer)";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rtk;
        description = "The rtk package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.rtk.enable) {
    home.packages = [ config.programs.rtk.package ];
  };
}
