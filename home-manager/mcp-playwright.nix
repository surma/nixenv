{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  inherit (config.programs) mcp-playwright;
in
{
  options = {
    programs.mcp-playwright = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = pkgs.mcp-playwright;
      };
    };
  };
  config = mkIf mcp-playwright.enable {
    home.packages = [ mcp-playwright.package ];
  };
}
