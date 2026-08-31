{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.key-poller;

  keyPoller = pkgs.stdenvNoCC.mkDerivation {
    pname = "key-poller";
    version = "1.0.0";
    src = ./key-poller.nu;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin $out/libexec
      cp $src $out/libexec/key-poller.nu
      chmod +x $out/libexec/key-poller.nu

      makeWrapper ${pkgs.nushell}/bin/nu $out/bin/key-poller \
        --add-flags $out/libexec/key-poller.nu \
        --set-default KEY_POLLER_SSH_BIN ${pkgs.openssh}/bin/ssh \
        --set-default KEY_POLLER_CURL_BIN ${pkgs.curl}/bin/curl \
        --set-default KEY_POLLER_JWT_BIN ${pkgs.jwt-cli}/bin/jwt \
        --set-default KEY_POLLER_SSH_USER ${escapeShellArg cfg.sshUser} \
        --set-default KEY_POLLER_SSH_IDENTITY_FILE ${escapeShellArg (toString cfg.sshIdentityFile)} \
        --set-default KEY_POLLER_KNOWN_HOSTS_FILE ${escapeShellArg "${cfg.stateDir}/known_hosts"} \
        --set-default KEY_POLLER_STATE_DIR ${escapeShellArg (toString cfg.stateDir)} \
        --set-default KEY_POLLER_SUCCESS_INTERVAL ${escapeShellArg cfg.successInterval} \
        --set-default KEY_POLLER_MAX_STALENESS ${escapeShellArg cfg.maxStaleness} \
        --set-default KEY_POLLER_SSH_HOSTS_JSON ${escapeShellArg (builtins.toJSON cfg.sshHosts)} \
        --set-default KEY_POLLER_RECEIVER_URL ${escapeShellArg cfg.receiverUrl} \
        --set-default KEY_POLLER_SECRET_FILE ${escapeShellArg (toString cfg.secretFile)} \
        --set-default KEY_POLLER_REMOTE_NU_BIN ${escapeShellArg cfg.remoteNuBin} \
        --set-default KEY_POLLER_REMOTE_GCLOUD_BIN ${escapeShellArg cfg.remoteGcloudBin}
    '';
  };
in
{
  options.services.key-poller = {
    enable = mkEnableOption "Shopify key poller";

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/key-poller";
      description = "Directory for key-poller state such as known_hosts and last-success";
    };

    sshUser = mkOption {
      type = types.str;
      default = "surma";
      description = "User to SSH as on shopisurm";
    };

    sshIdentityFile = mkOption {
      type = types.path;
      default = "/home/surma/.ssh/id_machine";
      description = "SSH identity file used by nexus to connect to shopisurm";
    };

    sshHosts = mkOption {
      type = types.listOf types.str;
      default = [
        "10.0.0.20"
        "100.79.232.5"
      ];
      description = "Shopisurm IPs to try in order";
    };

    receiverUrl = mkOption {
      type = types.str;
      default = "https://key.llm.surma.technology";
      description = "Base URL of the pylon key receiver";
    };

    secretFile = mkOption {
      type = types.path;
      description = "Path to the JWT signing secret used for the receiver";
    };

    successInterval = mkOption {
      type = types.str;
      default = "8h";
      description = "Time for which a successfully polled key stays fresh";
    };

    tickInterval = mkOption {
      type = types.str;
      default = "5min";
      description = "Interval between key-poller timer ticks";
    };

    maxStaleness = mkOption {
      type = types.str;
      default = "24h";
      description = "Maximum key age before a failed poll exits non-zero";
    };

    remoteNuBin = mkOption {
      type = types.str;
      default = "/etc/profiles/per-user/surma/bin/nu";
      description = "Path to nushell on shopisurm";
    };

    remoteGcloudBin = mkOption {
      type = types.str;
      default = "/etc/profiles/per-user/surma/bin/gcloud";
      description = "Path to gcloud on shopisurm";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ keyPoller ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    systemd.services.key-poller = {
      description = "Poll Shopify key from shopisurm and forward it to pylon";
      after = [
        "network-online.target"
        "secrets.service"
      ];
      wants = [
        "network-online.target"
        "secrets.service"
      ];
      restartIfChanged = false;
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${keyPoller}/bin/key-poller";
      };
    };

    systemd.timers.key-poller = {
      description = "Check key-poller periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.tickInterval;
        OnUnitActiveSec = cfg.tickInterval;
        Unit = "key-poller.service";
        Persistent = true;
      };
    };
  };
}
