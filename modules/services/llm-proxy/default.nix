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
    "${cfg.stateDir}/openrouter-key"
    "--openrouter-models"
    (builtins.toJSON cfg.providers.openrouter.models)
  ])
  ++ (lib.optionals cfg.clientAuth.enable [
    "--client-key-file"
    cfg.clientAuth.keyFile
  ])
  ++ (lib.optionals (cfg.database.enable && cfg.database.passwordFile != null) [
    "--database-host"
    cfg.database.host
    "--database-port"
    (toString cfg.database.port)
    "--database-name"
    cfg.database.database
    "--database-user"
    cfg.database.user
    "--database-password-file"
    cfg.database.passwordFile
  ])
  ++ (lib.optionals (cfg.masterKeyFile != null) [
    "--master-key-file"
    cfg.masterKeyFile
  ]);

  # Collect all key files that should be watched for changes
  watchedKeyFiles =
    (lib.optional cfg.providers.shopify.enable cfg.providers.shopify.keyFile)
    ++ (lib.optional (
      cfg.providers.openrouter.enable && cfg.providers.openrouter.keyFile != null
    ) cfg.providers.openrouter.keyFile)
    ++ (lib.optional (
      cfg.database.enable && cfg.database.passwordFile != null
    ) cfg.database.passwordFile)
    ++ (lib.optional (cfg.masterKeyFile != null) cfg.masterKeyFile);
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

        models = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            List of OpenRouter model IDs to expose.
            These will be prefixed with "openrouter:" in the LiteLLM config.
          '';
          example = [
            "qwen/qwen3-235b-a22b-2507"
            "anthropic/claude-opus-4.5"
          ];
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

    # PostgreSQL database configuration
    database = {
      enable = mkEnableOption "PostgreSQL database for virtual keys";

      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL host";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      database = mkOption {
        type = types.str;
        default = "litellm";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "litellm";
        description = "PostgreSQL user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing PostgreSQL password";
      };
    };

    # Master key for virtual key management
    masterKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing master key (must start with sk-)";
    };

    # UI configuration
    ui = {
      enableAdminUI = mkOption {
        type = types.bool;
        default = false;
        description = "Enable LiteLLM Admin UI";
      };

      disableDocs = mkOption {
        type = types.bool;
        default = true;
        description = "Disable Swagger and Redoc documentation";
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

    # Key receiver service
    systemd.services.llm-key-receiver = mkIf cfg.keyReceiver.enable {
      description = "LLM API Key Receiver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        LLM_KEY_RECEIVER_PORT = toString cfg.keyReceiver.port;
        LLM_KEY_RECEIVER_SECRET_FILE = cfg.keyReceiver.secretFile;
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
      after = [ "network.target" ];

      # Add Prisma CLI to PATH
      path = [ pkgs.python3Packages.prisma ];

      # Generate Prisma client and run migrations before starting
      preStart = mkIf cfg.database.enable ''
        # Set up environment for Prisma
        export HOME="${cfg.stateDir}"
        export DATABASE_URL="postgresql://${cfg.database.user}:$(cat ${cfg.database.passwordFile})@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.database}?sslmode=disable"

        # Copy schema.prisma to state directory if not exists or if source is newer
        SCHEMA_SOURCE="${pkgs.litellm}/lib/python${pkgs.python3.pythonVersion}/site-packages/litellm/proxy/schema.prisma"
        if [ ! -f "${cfg.stateDir}/schema.prisma" ] || [ "$SCHEMA_SOURCE" -nt "${cfg.stateDir}/schema.prisma" ]; then
          echo "Copying schema.prisma to state directory..."
          cp "$SCHEMA_SOURCE" "${cfg.stateDir}/schema.prisma"
        fi

        # Change to state directory
        cd "${cfg.stateDir}"

        # Generate Prisma client
        echo "Generating Prisma client..."
        prisma generate --schema=schema.prisma

        # Run database migrations
        echo "Running database migrations..."
        ${
          pkgs.python3.withPackages (ps: [
            ps.litellm
            ps.prisma
          ])
        }/bin/python3 \
          "${pkgs.litellm}/lib/python${pkgs.python3.pythonVersion}/site-packages/litellm/proxy/prisma_migration.py"

        echo "Prisma setup complete"
      '';

      environment = {
        # UI configuration
        DISABLE_ADMIN_UI = mkIf (!cfg.ui.enableAdminUI) "True";
        NO_DOCS = mkIf cfg.ui.disableDocs "True";
        NO_REDOC = mkIf cfg.ui.disableDocs "True";
      }
      // (lib.optionalAttrs cfg.database.enable {
        # Prisma configuration
        HOME = cfg.stateDir;
        PRISMA_PYTHON_CLIENT_PATH = "${cfg.stateDir}/generated";
      });

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Restart = "always";
        RestartSec = "10s";

        # Increased timeout for Prisma engine download on first run
        TimeoutStartSec = "180s";

        # Use wrapper script when database is enabled to set DATABASE_URL dynamically
        ExecStart =
          if cfg.database.enable then
            pkgs.writeShellScript "litellm-start" ''
              export DATABASE_URL="postgresql://${cfg.database.user}:$(cat ${cfg.database.passwordFile})@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.database}?sslmode=disable"
              export HOME="${cfg.stateDir}"
              export PRISMA_PYTHON_CLIENT_PATH="${cfg.stateDir}/generated"
              exec ${litellm-wrapper}/bin/litellm-wrapper ${lib.escapeShellArgs wrapperArgs}
            ''
          else
            "${litellm-wrapper}/bin/litellm-wrapper ${lib.escapeShellArgs wrapperArgs}";
      };
    };
  };
}
