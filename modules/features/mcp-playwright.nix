{ pkgs, config, lib, systemManager, inputs, ... }:
with lib;
{
  options = {
    programs.mcp-playwright = {
      enable = mkEnableOption "mcp-playwright server";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.system}.mcp-playwright;
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.mcp-playwright.enable) {
    home.packages = [ config.programs.mcp-playwright.package ];
  };
}
