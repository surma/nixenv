{ pkgs, config, lib, systemManager, inputs, ... }:
with lib;
{
  imports = [
    ../home-manager/pi-coding-agent/default-config.nix
  ];

  options = {
    programs.pi-coding-agent = {
      enable = mkEnableOption "Pi coding agent";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.pi-coding-agent;
        description = "The pi-coding-agent package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.pi-coding-agent.enable) {
    home.packages = [ config.programs.pi-coding-agent.package ];
  };
}
