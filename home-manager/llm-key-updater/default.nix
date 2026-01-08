{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.llm-key-updater;

  # The update script in nushell
  updateScript = pkgs.writeScriptBin "llm-key-update" ''
    #!${pkgs.nushell}/bin/nu

    let secret_file = "${cfg.secretFile}"

    # Get fresh Shopify key
    print "Getting fresh Shopify API key..."
    let key = get-shopify-key

    if ($key | str trim | str length) == 0 {
      error make { msg: "Got empty key from get-shopify-key" }
    }

    print "Got key, generating JWT..."
    let jwt = ${pkgs.jwt-cli}/bin/jwt encode -S $"@($secret_file)" -e="+5 minutes" '{}'

    print $"Sending key to ${cfg.target}/update..."
    let result = /usr/bin/curl -s -X POST -H $"Authorization: Bearer ($jwt)" -d $key "${cfg.target}/update"

    print $"Success: ($result)"
  '';

  # Calculate StartCalendarInterval based on intervalHours
  # We spread the intervals evenly throughout the day
  calendarIntervals =
    let
      hours = builtins.genList (i: i * cfg.intervalHours) (24 / cfg.intervalHours);
    in
    map (h: {
      Hour = h;
      Minute = 0;
    }) hours;
in
{
  options.services.llm-key-updater = {
    enable = mkEnableOption "Periodic Shopify LLM key updater";

    target = mkOption {
      type = types.str;
      example = "http://llm-key.nexus.hosts.10.0.0.2.nip.io";
      description = "URL of the key receiver endpoint (without /update path)";
    };

    secretFile = mkOption {
      type = types.path;
      description = "Path to file containing JWT signing secret";
    };

    intervalHours = mkOption {
      type = types.int;
      default = 8;
      description = "Hours between key updates (must evenly divide 24)";
    };

    retryIntervalSeconds = mkOption {
      type = types.int;
      default = 300;
      description = "Minimum seconds between retry attempts on failure";
    };

    logFile = mkOption {
      type = types.str;
      default = "/tmp/llm-key-updater.log";
      description = "Path to log file";
    };
  };

  config = mkIf cfg.enable {
    # Make the update script available in PATH
    home.packages = [ updateScript ];

    # Configure launchd agent
    launchd.enable = true;
    launchd.agents.llm-key-updater = {
      enable = true;
      config = {
        Label = "dev.surma.llm-key-updater";
        ProgramArguments = [ "${updateScript}/bin/llm-key-update" ];

        # Run at specified intervals
        StartCalendarInterval = calendarIntervals;

        # Also run when volumes are mounted (triggers on wake from sleep)
        StartOnMount = true;

        # Run once when the agent is loaded
        RunAtLoad = true;

        # Retry on failure: restart if exit code is non-zero
        KeepAlive = {
          SuccessfulExit = false;
        };

        # Minimum time between restart attempts
        ThrottleInterval = cfg.retryIntervalSeconds;

        # Logging
        StandardOutPath = cfg.logFile;
        StandardErrorPath = cfg.logFile;

        # Environment - ensure PATH includes necessary tools
        EnvironmentVariables = {
          PATH = lib.makeBinPath [
            pkgs.nushell
            pkgs.jwt-cli
            pkgs.coreutils
            pkgs.curl
            # get-shopify-key and its dependencies
            config.customScripts.get-shopify-key.package
            pkgs.google-cloud-sdk
          ];
        };
      };
    };
  };
}
