{ pkgs, ... }:
{
  secrets.items.github-runner-pat = {
    target = "/var/lib/github-runner/token";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /dump/state/github-runner 0755 root root - -"
  ];

  services.surmhosting.services.github-runner.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig = {
      MemoryMax = "8G";
      MemorySwapMax = "8G";
    };
  };

  services.surmhosting.services.github-runner.container = {
    bindMounts = {
      state = {
        mountPoint = "/var/lib/github-runner";
        hostPath = "/dump/state/github-runner";
        isReadOnly = false;
      };
      token = {
        mountPoint = "/var/lib/credentials/github-runner";
        hostPath = "/var/lib/github-runner";
        isReadOnly = true;
      };
    };

    config = {
      system.stateVersion = "25.05";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];

      users.users.containeruser = {
        isNormalUser = true;
        group = "users";
        home = "/home/containeruser";
        extraGroups = [ "nixbld" ];
      };

      systemd.tmpfiles.rules = [
        "d /home/containeruser 0755 containeruser users - -"
        "d /var/lib/github-runner/work 0755 containeruser users - -"
      ];

      services.github-runners.sl = {
        enable = true;
        url = "https://github.com/surma/sl";
        tokenFile = "/var/lib/credentials/github-runner/token";
        name = "nexus-sl-nix-x64";
        replace = true;
        runnerGroup = "Default";
        user = "containeruser";
        group = "users";
        workDir = "/var/lib/github-runner/work";
        extraLabels = [
          "nix"
          "nixos"
          "nexus"
          "container"
          "x64"
          "sl"
        ];
        extraPackages = with pkgs; [
          bash
          coreutils
          curl
          git
          gnutar
          gzip
          jq
          nushell
          zstd
        ];
        serviceOverrides = {
          StateDirectory = [ "github-runner/sl" ];
          RuntimeDirectory = [ "github-runner/sl" ];
          LogsDirectory = [ "github-runner/sl" ];
          ProtectHome = false;
          PrivateUsers = false;
          PrivateMounts = false;
        };
      };
    };
  };
}
