{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config.programs) claude-code;
  inherit (pkgs) writeShellScriptBin;

  mcpServerType = import ../../../lib/module-types/mcp-server.nix lib;

  wrapper = writeShellScriptBin "claude" ''
    ${lib.optionalString (claude-code.overrides.baseURL != null) ''
      export ANTHROPIC_BASE_URL="${claude-code.overrides.baseURL}"
    ''}
    ${lib.optionalString (claude-code.overrides.apiKey != null) ''
      # Read API key from file and export as env var (only in this subprocess)
      if [ -f "${claude-code.overrides.apiKey}" ]; then
        export ANTHROPIC_API_KEY=$(cat "${claude-code.overrides.apiKey}" | tr -d '\n')
      fi
    ''}
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';
in
with lib;
{

  imports = [
    ./default-config.nix
  ];

  options = {
    programs.claude-code = {
      overrides.baseURL = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Base URL for the Anthropic API";
      };
      overrides.apiKey = mkOption {
        type = with types; nullOr path;
        default = null;
        description = "Path to file containing the API key";
      };
      mcps = mkOption {
        type = types.attrsOf mcpServerType;
        default = { };
      };
    };
  };
  config = mkIf claude-code.enable {
    programs.claude-code.package = wrapper;
  };
}
