{ pkgs, config, lib, systemManager, ... }:
with lib;
let
  inherit (config.programs) opencode;

  mcpServerDefinition = {
    options = {
      type = mkOption {
        type = types.enum [ "local" ];
      };
      command = mkOption {
        type = with types; oneOf [ str (listOf str) ];
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

  fullConfig = baseConfig // {
    mcp = opencode.mcps;
  } // opencode.extraConfig;
in
{
  imports = [
    ../home-manager/opencode/default-config.nix
  ];

  options = {
    programs.opencode = {
      extraConfig = mkOption {
        type = types.attrs;
        default = { };
      };
      mcps = mkOption {
        type = types.attrsOf (types.submodule mcpServerDefinition);
        default = { };
      };
      plugins = mkOption {
        type = types.attrsOf types.lines;
        default = { };
        description = "Plugin files to write to ~/.config/opencode/plugin/";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && opencode.enable) {
    xdg.configFile = mkMerge [
      { "opencode/config.json".text = builtins.toJSON fullConfig; }
      (lib.mapAttrs' (name: content: {
        name = "opencode/plugin/${name}";
        value = {
          text = content;
        };
      }) opencode.plugins)
    ];
  };
}
