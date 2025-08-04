{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config.programs) claude-code;
  inherit (pkgs) writeShellScriptBin;

  mcpServerType = import ../../lib/module-types/mcp-server.nix lib;

  defaultClaudeJson =
    {
      hasCompletedOnboarding = true;
      mcps = claude-code.mcps;
    }
    |> builtins.toJSON
    |> builtins.toFile "dot-claude-json";

  wrapper = writeShellScriptBin "claude" ''
    ${lib.optionalString (claude-code.overrides.baseURL != null) ''
      export ANTHROPIC_BASE_URL="${claude-code.overrides.baseURL}"
    ''}
    ${lib.optionalString (claude-code.overrides.apiKey != null) ''
      export ANTHROPIC_API_KEY=${claude-code.overrides.apiKey}
    ''}
    ${claude-code.package}/bin/claude "$@"
  '';
in
with lib;
{

  imports = [
    ./default-config.nix
  ];

  options = {
    programs.claude-code = {
      enable = mkEnableOption "";
      overrides.baseURL = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      overrides.apiKey = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      package = mkOption {
        type = types.package;
        default = pkgs.claude-code;
      };
      mcps = mkOption {
        type = types.attrsOf mcpServerType;
        default = { };
      };
    };
  };
  config = mkIf claude-code.enable {
    home.activation.copyClaudeJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -f ~/.claude.json ]; then
        cp ${defaultClaudeJson} ~/.claude.json
        chmod 644 ~/.claude.json
      fi
    '';

    home.packages = [ wrapper ];
  };
}
