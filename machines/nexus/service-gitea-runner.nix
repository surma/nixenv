{ pkgs, lib, ... }:
let
  ips = import ../../ips.nix;
  giteaUrl = "http://gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081";
  syncRunnerUrl = pkgs.writeShellScript "sync-gitea-runner-url" ''
    set -euo pipefail

    runnerFile="$STATE_DIRECTORY/websearchcli/.runner"
    expectedUrl=${lib.escapeShellArg giteaUrl}

    if [[ -f "$runnerFile" ]]; then
      currentUrl="$(${pkgs.jq}/bin/jq --raw-output '.address // ""' "$runnerFile")"
      if [[ "$currentUrl" != "$expectedUrl" ]]; then
        ${pkgs.jq}/bin/jq --arg address "$expectedUrl" '.address = $address' "$runnerFile" > "$runnerFile.tmp"
        ${pkgs.coreutils}/bin/chmod --reference="$runnerFile" "$runnerFile.tmp"
        ${pkgs.coreutils}/bin/mv "$runnerFile.tmp" "$runnerFile"
      fi
    fi
  '';
in
{
  secrets.items.gitea-web-search-cli-runner-token = {
    target = "/var/lib/gitea-runner/token.env";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /dump/state/gitea-runner 0755 root root - -"
    "d /var/lib/gitea-runner 0755 root root - -"
  ];

  services.surmhosting.services.gitea-runner.backend."nixos-container".service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig = {
      MemoryMax = "16G";
      MemorySwapMax = "0";
    };
  };

  services.surmhosting.services.gitea-runner.backend."nixos-container" = {
    bindMounts = {
      state = {
        mountPoint = "/var/lib/gitea-runner";
        hostPath = "/dump/state/gitea-runner";
        isReadOnly = false;
      };
      token = {
        mountPoint = "/var/lib/credentials/gitea-runner";
        hostPath = "/var/lib/gitea-runner";
        isReadOnly = true;
      };
    };

    config = {
      system.stateVersion = "25.05";

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
      };

      users.users.containeruser = {
        isNormalUser = true;
        group = "users";
        home = "/home/containeruser";
        extraGroups = [ "nixbld" ];
      };

      systemd.tmpfiles.rules = [
        "d /home/containeruser 0755 containeruser users - -"
      ];

      services.gitea-actions-runner.instances.websearchcli = {
        enable = true;
        name = "nexus-web-search-cli-nix-x64";
        url = giteaUrl;
        tokenFile = "/var/lib/credentials/gitea-runner/token.env";
        labels = [ "nixos:host" ];
        hostPackages = with pkgs; [
          bash
          coreutils
          curl
          gitMinimal
          gnutar
          gzip
          jq
          nix
          nodejs
          nushell
          wget
          zstd
        ];
        settings = {
          runner.capacity = 2;
          runner.timeout = "30m";
        };
      };

      systemd.services."gitea-runner-websearchcli" = {
        wantedBy = lib.mkForce [ ];
        unitConfig.ConditionPathExists = "/var/lib/credentials/gitea-runner/token.env";
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce "containeruser";
          Group = lib.mkForce "users";
          # The upstream module does not re-register when only the URL changes.
          ExecStartPre = lib.mkBefore [ syncRunnerUrl ];
        };
      };

      systemd.timers."gitea-runner-websearchcli-delayed-start" = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10s";
          Unit = "gitea-runner-websearchcli.service";
        };
      };
    };
  };
}
