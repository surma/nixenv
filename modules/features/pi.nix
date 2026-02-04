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
  imports = [
    ../home-manager/pi/default-config.nix
    ../programs/pi/extensions/plan-mode
  ];

  options = {
    programs.pi = {
      enable = mkEnableOption "Pi";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.pi-coding-agent;
        description = "The pi-coding-agent package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.pi.enable) {
    home.packages = [ config.programs.pi.package ];
  };
}
