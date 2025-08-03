{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (pkgs) browser-mcp;
in
with lib;
{
  options = {
    programs.browser-mcp = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = browser-mcp;
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
