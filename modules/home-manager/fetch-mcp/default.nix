{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    programs.fetch-mcp = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = pkgs.fetch-mcp;
      };
    };
  };
  config =
    let
      inherit (config.programs) fetch-mcp;
    in
    mkIf fetch-mcp.enable {
      home.packages = [ fetch-mcp.package ];
    };
}
