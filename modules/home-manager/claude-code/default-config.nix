{
  pkgs,
  config,
  lib,
  ...
}:
let
  isEnabled = config.defaultConfigs.claude-code.enable;
  cfg = config.defaultConfigs.claude-code.llmProxy;
in
with lib;
{
  options = {
    defaultConfigs.claude-code = {
      enable = mkEnableOption "";

      llmProxy = {
        baseURL = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology/anthropic-claude-code";
          description = "Base URL for the Anthropic vendor route on your LLM proxy";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = lib.attrByPath [ "secrets" "items" "llm-proxy-client-key" "target" ] null config;
          description = "Path to file containing the API key for the LLM proxy";
        };
      };
    };
  };

  config = mkMerge [
    {
      programs.claude-code = mkIf isEnabled {
        enable = true;
        overrides.baseURL = cfg.baseURL;
        overrides.apiKey = mkIf (cfg.apiKeyFile != null) cfg.apiKeyFile;
      };
    }

    # Add activation script to manage ~/.claude.json with jq-based merging
    (mkIf (isEnabled && cfg.apiKeyFile != null) {
      home.activation.updateClaudeJson = lib.hm.dag.entryAfter [ "writeBoundary" "secrets" ] ''
        CLAUDE_JSON="$HOME/.claude.json"

        # Create file with minimal defaults if it doesn't exist
        if [ ! -f "$CLAUDE_JSON" ]; then
          echo '{"hasCompletedOnboarding": true}' > "$CLAUDE_JSON"
        fi

        # Prepare MCP configurations as JSON
        MCPS='${builtins.toJSON config.programs.claude-code.mcps}'

        # Update configuration using jq:
        # 1. Merge Nix-configured MCPs with existing ones (Nix configs take precedence)
        # 2. Preserve all other fields
        ${pkgs.jq}/bin/jq \
          --argjson nixMcps "$MCPS" \
          '.mcps = (.mcps // {}) + $nixMcps' \
          "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"

        mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
        chmod 600 "$CLAUDE_JSON"
      '';
    })
  ];
}
