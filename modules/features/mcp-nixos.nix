{ pkgs, config, lib, systemManager, inputs, ... }:
with lib;
{
  options = {
    programs.mcp-nixos = {
      enable = mkEnableOption "mcp-nixos server";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.mcp-nixos;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.mcp-nixos.enable) {
    home.packages = [ config.programs.mcp-nixos.package ];
  };
}
