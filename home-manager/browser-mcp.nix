{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    programs.browser-mcp = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = pkgs.browser-mcp;
      };
    };
  };
  config =
    let
      inherit (config.programs) browser-mcp;
    in
    mkIf browser-mcp.enable {
      home.packages = [ browser-mcp.package ];
    };
}
