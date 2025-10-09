{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  inherit (config.programs) opencode;

  mcpServerDefinition = {
    options = {
      type = mkOption {
        type = types.enum [ "local" ];
      };
      command = mkOption {
        type =
          with types;
          oneOf [
            str
            (listOf str)
          ];
        apply = (s: if builtins.isString s then [ s ] else s);
      };
      environment = mkOption {
        type = with types; attrsOf str;
        default = { };
      };
    };
  };

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
        type = types.attrsOf (types.submodule mcpServerDefinition);
        default = { };
      };
    };
  };
  config = mkIf opencode.enable {
    xdg.configFile."opencode/config.json".text = builtins.toJSON fullConfig;
    home.packages = [ opencode.package ];
  };
}
