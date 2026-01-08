{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.llm-proxy;

  key-receiver = pkgs.callPackage ./key-receiver { };

  litellm-wrapper = pkgs.writeScriptBin "litellm-wrapper" ''
    #!${pkgs.nushell}/bin/nu
    ${builtins.readFile ./litellm-wrapper.nu |> lib.removePrefix "#!/usr/bin/env nu\n"}
  '';

  # Build the wrapper arguments based on enabled providers
  wrapperArgs = [
    "--config"
    cfg.configFile
    "--port"
    (toString cfg.port)
    "--litellm"
    "${pkgs.litellm}/bin/litellm"
  ]
  ++ (lib.optionals cfg.providers.shopify.enable [
    "--shopify-key-file"
    cfg.providers.shopify.keyFile
  ])
  ++ (lib.optionals (cfg.providers.openrouter.enable && cfg.providers.openrouter.keyFile != null) [
    "--openrouter-key-file"
    cfg.providers.openrouter.keyFile
  ])
  ++ (lib.optionals cfg.clientAuth.enable [
    "--client-key-file"
    "${cfg.stateDir}/client-key"
  ]);

  # Collect all key files that should be watched for changes
  watchedKeyFiles =
    (lib.optional cfg.providers.shopify.enable cfg.providers.shopify.keyFile)
    ++ (lib.optional (
      cfg.providers.openrouter.enable && cfg.providers.openrouter.keyFile != null
    ) cfg.providers.openrouter.keyFile);
in
{
  options.services.llm-proxy = {
    enable = mkEnableOption "LLM proxy service with dynamic key updates";

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/llm-proxy";
      description = "Directory for state files (keys, config)";
    };

    configFile = mkOption {
      type = types.path;
      default = "/var/lib/llm-proxy/config.yml";
      description = "Path to generated LiteLLM config file";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port for LiteLLM API";
    };

    user = mkOption {
      type = types.str;
      default = "llm-proxy";
      description = "User to run the services as";
    };

    keyReceiver = {
      enable = mkEnableOption "Key receiver HTTP endpoint";

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for key receiver HTTP endpoint";
      };

      secretFile = mkOption {
        type = types.path;
        description = "Path to file containing JWT signing secret";
      };

      keyFile = mkOption {
        type = types.path;
        default = cfg.providers.shopify.keyFile;
        description = "Path where received keys will be written";
      };
    };

    providers = {
      shopify = {
        enable = mkEnableOption "Shopify AI proxy provider";

        keyFile = mkOption {
          type = types.path;
          default = "/var/lib/llm-proxy/shopify-key";
          description = "Path to Shopify API key file (updated by key receiver)";
        };
      };

      openrouter = {
        enable = mkEnableOption "OpenRouter provider";

        keyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to OpenRouter API key file";
        };
      };
    };

    clientAuth = {
      enable = mkEnableOption "Require API key for LLM API clients";

      keyFile = mkOption {
        type = types.path;
        description = "Path to file containing the static API key (should start with sk-)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create the llm-proxy user
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.stateDir;
    };
    users.groups.${cfg.user} = { };

    # Ensure state directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.user} -"
    ];

    # Service to copy secrets with correct ownership (runs as root)
    systemd.services.llm-proxy-copy-secrets = mkIf (cfg.keyReceiver.enable || cfg.clientAuth.enable) {
      description = "Copy secrets for LLM proxy services";
      wantedBy = [ "multi-user.target" ];
      before = [
        "llm-key-receiver.service"
        "litellm.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "copy-llm-proxy-secrets" ''
          ${lib.optionalString cfg.keyReceiver.enable ''
            cp ${cfg.keyReceiver.secretFile} ${cfg.stateDir}/receiver-secret
            chown ${cfg.user}:${cfg.user} ${cfg.stateDir}/receiver-secret
            chmod 0600 ${cfg.stateDir}/receiver-secret
          ''}
          ${lib.optionalString cfg.clientAuth.enable ''
            cp ${cfg.clientAuth.keyFile} ${cfg.stateDir}/client-key
            chown ${cfg.user}:${cfg.user} ${cfg.stateDir}/client-key
            chmod 0600 ${cfg.stateDir}/client-key
          ''}
        '';
      };
    };

    # Key receiver service
    systemd.services.llm-key-receiver = mkIf cfg.keyReceiver.enable {
      description = "LLM API Key Receiver";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "llm-proxy-copy-secrets.service"
      ];
      requires = [ "llm-proxy-copy-secrets.service" ];

      environment = {
        LLM_KEY_RECEIVER_PORT = toString cfg.keyReceiver.port;
        LLM_KEY_RECEIVER_SECRET_FILE = "${cfg.stateDir}/receiver-secret";
        LLM_KEY_RECEIVER_KEY_FILE = cfg.keyReceiver.keyFile;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${key-receiver}/bin/llm-key-receiver";
        User = cfg.user;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # Path units to watch for key file changes
    systemd.paths.litellm-watcher = mkIf (watchedKeyFiles != [ ]) {
      description = "Watch for LLM key file changes";
      wantedBy = [ "multi-user.target" ];

      pathConfig = {
        PathChanged = watchedKeyFiles;
        Unit = "litellm-restart.service";
      };
    };

    # Service to restart litellm when key changes
    systemd.services.litellm-restart = mkIf (watchedKeyFiles != [ ]) {
      description = "Restart LiteLLM on key change";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart litellm.service";
      };
    };

    # LiteLLM service
    systemd.services.litellm = {
      description = "LiteLLM Proxy Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optional cfg.clientAuth.enable "llm-proxy-copy-secrets.service";
      requires = lib.optional cfg.clientAuth.enable "llm-proxy-copy-secrets.service";

      serviceConfig = {
        Type = "simple";
        ExecStart = "${litellm-wrapper}/bin/litellm-wrapper ${lib.escapeShellArgs wrapperArgs}";
        User = cfg.user;
        Restart = "always";
        RestartSec = "10s";

        # Give it time to fetch models on startup
        TimeoutStartSec = "120s";
      };
    };
  };
}
