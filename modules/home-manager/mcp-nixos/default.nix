{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    programs.mcp-nixos = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = pkgs.mcp-nixos;
      };
    };
  };
  config =
    let
      inherit (config.programs) mcp-nixos;
    in
    mkIf mcp-nixos.enable {
      home.packages = [ mcp-nixos.package ];
    };
}
