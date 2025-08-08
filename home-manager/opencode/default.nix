{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config.programs) opencode;

  mcpServerType = import ../../lib/module-types/mcp-server.nix lib;

  baseConfig = {
    "$schema" = "https://opencode.ai/config.json";
  };
  fullConfig =
    baseConfig
    // {
      mcp = opencode.mcps;
    }
    // opencode.extraConfig;
in
with lib;
{
  imports = [
    ./default-config.nix
  ];

  options = {
    programs.opencode = {
      enable = mkEnableOption "";
      package = mkOption {
        type = types.package;
        default = pkgs.opencode;
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = { };
      };
      mcps = mkOption {
        type = types.attrsOf mcpServerType;
        default = { };
      };
    };
  };
  config = mkIf opencode.enable {
    xdg.configFile."opencode/config.json".text = builtins.toJSON fullConfig;
    home.packages = [ opencode.package ];
  };
}
