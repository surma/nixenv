{ pkgs, lib, ... }:
{
  secrets.items.gitea-web-search-cli-runner-token = {
    target = "/var/lib/gitea-runner/token.env";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /dump/state/gitea-runner 0755 root root - -"
    "d /var/lib/gitea-runner 0755 root root - -"
  ];

  services.surmhosting.services.gitea-runner.containerName = "gitea-runner";
  services.surmhosting.services.gitea-runner.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig = {
      MemoryMax = "8G";
      MemorySwapMax = "8G";
    };
  };

  services.surmhosting.services.gitea-runner.container = {
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

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      nix.settings.trusted-users = [
        "root"
        "containeruser"
      ];

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
        url = "https://gitea.surma.technology";
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
          runner.capacity = 1;
        };
      };

      systemd.services."gitea-runner-websearchcli" = {
        unitConfig.ConditionPathExists = "/var/lib/credentials/gitea-runner/token.env";
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce "containeruser";
          Group = lib.mkForce "users";
        };
      };
    };
  };
}
