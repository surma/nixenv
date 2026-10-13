{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  isEnabled = config.defaultConfigs.pi.enable;
  piCfg = config.defaultConfigs.pi;
  llmProxyCfg = piCfg.llmProxy;
  openRouterCfg = piCfg.openRouter;
  proxyExtensionCfg = piCfg.extensions.proxy;
  mcpAdapterCfg = piCfg.packages.mcpAdapter;
  palette = import ../../../lib/sx-palette.nix { inherit inputs; };
  sxPaletteData = builtins.fromJSON (builtins.readFile "${inputs.sx}/assets/palette/palette.json");

  sxDarkTheme = {
    name = "sx-dark";
    appearance = "dark";
    colors = {
      accent = palette.blue;
      border = palette.graphite;
      borderAccent = palette.steel;
      borderMuted = palette.gunmetal;
      success = palette.go;
      error = palette.halt;
      warning = palette.caution;
      muted = palette.ash;
      dim = palette.ash;
      text = palette.bone;
      thinkingText = palette.ash;
      selectedBg = palette.gunmetal;
      userMessageBg = palette.gunmetal;
      userMessageText = palette.bone;
      customMessageBg = palette.gunmetal;
      customMessageText = palette.ash;
      customMessageLabel = palette.magenta;
      toolPendingBg = palette.gunmetal;
      toolSuccessBg = sxPaletteData.ramps.green."33".srgb;
      toolErrorBg = sxPaletteData.ramps.red."33".srgb;
      toolTitle = palette.bone;
      toolOutput = palette.ash;
      mdHeading = palette.cyan;
      mdLink = palette.blue;
      mdLinkUrl = palette.ash;
      mdCode = palette.cyan;
      mdCodeBlock = palette.go;
      mdCodeBlockBorder = palette.graphite;
      mdQuote = palette.ash;
      mdQuoteBorder = palette.graphite;
      mdHr = palette.graphite;
      mdListBullet = palette.magenta;
      toolDiffAdded = palette.go;
      toolDiffRemoved = palette.halt;
      toolDiffContext = palette.ash;
      syntaxComment = palette.ash;
      syntaxKeyword = palette.magenta;
      syntaxFunction = palette.blue;
      syntaxVariable = palette.cyan;
      syntaxString = palette.go;
      syntaxNumber = palette.caution;
      syntaxType = palette.magenta;
      syntaxOperator = palette.cyan;
      syntaxPunctuation = palette.ash;
      thinkingOff = palette.gunmetal;
      thinkingMinimal = palette.graphite;
      thinkingLow = palette.blue;
      thinkingMedium = palette.cyan;
      thinkingHigh = palette.magenta;
      thinkingXhigh = palette.magenta;
      bashMode = palette.cyan;
    };
    export = {
      pageBg = palette.carbon;
      cardBg = palette.gunmetal;
      infoBg = palette.gunmetal;
    };
  };

  sxLightTheme = {
    name = "sx-light";
    appearance = "light";
    colors = {
      accent = palette."blue-deep";
      border = palette.concrete;
      borderAccent = palette.concrete;
      borderMuted = palette.concrete;
      success = palette."go-deep";
      error = palette."halt-deep";
      warning = palette."caution-deep";
      muted = palette.graphite;
      dim = palette.graphite;
      text = palette.carbon;
      thinkingText = palette.graphite;
      selectedBg = palette.concrete;
      userMessageBg = palette.concrete;
      userMessageText = palette.carbon;
      customMessageBg = palette.concrete;
      customMessageText = palette.graphite;
      customMessageLabel = palette."magenta-deep";
      toolPendingBg = palette.concrete;
      toolSuccessBg = sxPaletteData.ramps.green."96".srgb;
      toolErrorBg = sxPaletteData.ramps.red."96".srgb;
      toolTitle = palette.carbon;
      toolOutput = palette.graphite;
      mdHeading = palette."cyan-deep";
      mdLink = palette."blue-deep";
      mdLinkUrl = palette.graphite;
      mdCode = palette."cyan-deep";
      mdCodeBlock = palette."go-deep";
      mdCodeBlockBorder = palette.concrete;
      mdQuote = palette.graphite;
      mdQuoteBorder = palette.concrete;
      mdHr = palette.concrete;
      mdListBullet = palette."magenta-deep";
      toolDiffAdded = palette."go-deep";
      toolDiffRemoved = palette."halt-deep";
      toolDiffContext = palette.graphite;
      syntaxComment = palette.graphite;
      syntaxKeyword = palette."magenta-deep";
      syntaxFunction = palette."blue-deep";
      syntaxVariable = palette."cyan-deep";
      syntaxString = palette."go-deep";
      syntaxNumber = palette."caution-deep";
      syntaxType = palette."magenta-deep";
      syntaxOperator = palette."cyan-deep";
      syntaxPunctuation = palette.graphite;
      thinkingOff = palette.concrete;
      thinkingMinimal = palette.concrete;
      thinkingLow = palette."blue-deep";
      thinkingMedium = palette."cyan-deep";
      thinkingHigh = palette."magenta-deep";
      thinkingXhigh = palette."magenta-deep";
      bashMode = palette."cyan-deep";
    };
    export = {
      pageBg = palette.bone;
      cardBg = palette.concrete;
      infoBg = palette.concrete;
    };
  };

  defaultSettings = {
    defaultProvider = "anthropic";
    defaultModel = "claude-opus-5-5";
    defaultThinkingLevel = "xhigh";
    steeringMode = "all";
    compaction = {
      enabled = true;
      reserveTokens = 32000;
    };
    packages = [
      {
        source = "ssh://git@github.com/surma/pi-config";
        extensions = [ "-extensions/proxy.ts" ];
        prompts = [ ];
      }
    ];
    theme = "sx-light/sx-dark";
  };

  settings =
    let
      mergedSettings = lib.recursiveUpdate defaultSettings piCfg.settings;
      extraPackages = lib.optional mcpAdapterCfg.enable "npm:pi-mcp-adapter" ++ piCfg.extraPackages;
    in
    mergedSettings
    // lib.optionalAttrs (extraPackages != [ ]) {
      packages = (mergedSettings.packages or [ ]) ++ extraPackages;
    };

  wrapper = pkgs.writeShellScriptBin "pi" ''
    export PI_SUBAGENT_PI_BIN="$0"

    ${lib.optionalString (llmProxyCfg.apiKeyFile != null) ''
      if [ -f "${llmProxyCfg.apiKeyFile}" ]; then
        export PI_PROXY_API_KEY="$(tr -d '\n' < "${llmProxyCfg.apiKeyFile}")"
      fi

      if [ -n "''${PI_PROXY_API_KEY:-}" ]; then
        export PI_PROXY_AUTH_HEADER="Bearer ''${PI_PROXY_API_KEY}"
        # The extractive compaction extension in pi-config reads this.
        export PI_DECISIONS_URL=${lib.escapeShellArg "${llmProxyCfg.vendorBaseURL}/openai-shopify-shopapp-chatgpt-prod/v1/decisions"}
      fi
    ''}

    ${lib.optionalString (openRouterCfg.keyFile != null) ''
      if [ -f "${openRouterCfg.keyFile}" ]; then
        export OPENROUTER_API_KEY="$(tr -d '\n' < "${openRouterCfg.keyFile}")"
      fi
    ''}

    export PI_PROXY_BASE_URL=${lib.escapeShellArg llmProxyCfg.vendorBaseURL}
    export PI_SKIP_VERSION_CHECK=1

    exec ${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-coding-agent}/bin/pi "$@"
  '';
in
with lib;
{
  options = {
    defaultConfigs.pi = {
      enable = mkEnableOption "";

      settings = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional Pi settings merged into ~/.pi/agent/settings.json";
      };

      extraPackages = mkOption {
        type = types.listOf (types.either types.str (types.attrsOf types.anything));
        default = [ ];
        description = "Extra Pi packages concatenated into settings.json packages. Merges across modules.";
      };

      llmProxy = {
        vendorBaseURL = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology";
          description = "Base URL for Shopify proxy passthrough routes";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = lib.attrByPath [ "secrets" "items" "llm-proxy-client-key" "target" ] null config;
          description = "Path to file containing the API key for the LLM proxy";
        };
      };

      openRouter.keyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing the OpenRouter API key";
      };

      extensions.proxy.enable = mkEnableOption "the machine-local Pi proxy extension";

      extensions.contextUsage.enable = mkEnableOption "the context-usage awareness extension (injects usage warnings into prompts)";

      extensions.subagent.enable = mkEnableOption "the subagent extension (persistent child Pi processes via RPC)";

      extensions.listModels.enable = mkEnableOption "the list-models extension (list_models tool)";

      extensions.skillAliases.enable = mkEnableOption "the skill-aliases extension (bare /skill aliases + autocomplete)";

      packages.mcpAdapter.enable = mkEnableOption "the pi-mcp-adapter Pi package";

      mcpConfig = mkOption {
        type = types.nullOr (types.attrsOf types.anything);
        default = null;
        description = "JSON content written to ~/.pi/agent/mcp.json";
      };
    };
  };

  config = mkMerge [
    {
      programs.pi = mkIf isEnabled {
        enable = true;
      };

      home.file = mkIf isEnabled (
        {
          ".pi/agent/settings.json" = {
            text = builtins.toJSON settings;
            mutable = true;
          };
          ".pi/agent/themes/sx-dark.json".text = builtins.toJSON sxDarkTheme;
          ".pi/agent/themes/sx-light.json".text = builtins.toJSON sxLightTheme;
          ".pi/agent/APPEND_SYSTEM.md".source = ../../../assets/pi/APPEND_SYSTEM.md;
        }
        // optionalAttrs (piCfg.mcpConfig != null) {
          ".pi/agent/mcp.json" = {
            text = builtins.toJSON piCfg.mcpConfig;
            mutable = true;
          };
        }
        // optionalAttrs proxyExtensionCfg.enable {
          ".pi/agent/extensions/proxy.ts" = {
            source = ./extension/proxy.ts;
            force = true;
          };
        }
        // optionalAttrs piCfg.extensions.contextUsage.enable {
          ".pi/agent/extensions/context-usage.ts".source = ./extension/context-usage.ts;
        }
        // optionalAttrs piCfg.extensions.listModels.enable {
          ".pi/agent/extensions/list-models.ts".source = ./extension/list-models.ts;
        }
        // optionalAttrs piCfg.extensions.skillAliases.enable {
          ".pi/agent/extensions/skill-aliases.ts".source = ./extension/skill-aliases.ts;
        }
        // optionalAttrs piCfg.extensions.subagent.enable {
          ".pi/agent/extensions/subagent".source = ./extension/subagent;
        }
      );
    }

    (mkIf
      (
        isEnabled
        && (llmProxyCfg.apiKeyFile != null || openRouterCfg.keyFile != null || proxyExtensionCfg.enable)
      )
      {
        programs.pi.package = wrapper;
      }
    )
  ];
}
