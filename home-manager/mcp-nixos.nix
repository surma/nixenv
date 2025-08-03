{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (pkgs) mcp-nixos;
in
with lib;
{
  options = {
    programs.mcp-nixos = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = mcp-nixos;
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
