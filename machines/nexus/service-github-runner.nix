{ pkgs, lib, ... }:
let
  ips = import ../../ips.nix;
  giteaHost = "gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io";

  surmaRepos = [
    "sl"
    "parakeeb"
    "Haven"
    "brain"
    "nixenv"
  ];

  # nixenv has private git+ssh flake inputs on GitHub and Gitea. Only the
  # nixenv runner may read the repo key (see service-scout.nix for the
  # secret command that writes it).
  repoKeyPath = "/var/lib/credentials/github-runner/id_repo_scout";

  # The nixenv CI workflow pins its latest main builds here, so that Nexus's
  # GC keeps them and Harmonia (service-nix-cache.nix) can serve them. Inside
  # the container, /nix/var/nix/gcroots is the host's per-container gcroots
  # directory, which the host GC scans.
  nixenvGcRootsDir = "/nix/var/nix/gcroots/nixenv-ci";
in
{
  secrets.items.github-runner-pat = {
    target = "/var/lib/github-runner/token";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d- /dump/state/github-runner 0755 root root - -"
  ];

  services.surmhosting.services.github-runner.backend."nixos-container".service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig = {
      # Evaluating the nexus system for the nixenv CI build needs about
      # 11 GB. The builds themselves run in the host's nix-daemon.
      MemoryMax = "16G";
      MemorySwapMax = "8G";
    };
  };

  services.surmhosting.services.github-runner.backend."nixos-container" = {
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

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
      };

      # The runner sets HOME to its work dir and mounts / read-only, so SSH
      # settings and host keys for flake inputs must be system-wide.
      programs.ssh.extraConfig = ''
        Host github.com
          User git
          IdentitiesOnly yes
          IdentityFile ${repoKeyPath}

        Host gitea.surma.technology ${giteaHost}
          HostName ${giteaHost}
          HostKeyAlias ${giteaHost}
          Port 2222
          User containeruser
          IdentitiesOnly yes
          IdentityFile ${repoKeyPath}
      '';
      programs.ssh.knownHosts = {
        "github.com".publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        ${giteaHost}.publicKey =
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCXZY/qU6Hto1Z44kGLaKalVjYNCh6UeRMfn3FphKYmaJ6fCwYPP0d/RACzXD6+pOyv/tsLb7lcCoVxKyatAQflFJd2MGuapZpoimFrXQnb3qL0yDyYN6fa/8bHF06BFYxAH3PjNEmx6VFsFT9GSgFSTygbkeQRgcLnwvz54Gd9YeAi7hzts0J4UOZNAdBnuoGcOddVN5sNBjHknhG8Iyg/feRoEKV/HtyTOONfEWgqzHmikk8i/D4/6Uo9Z+4YZvJvURLS9WOTtpirwjLbUUaj9RaoHRXx6IHQ6SFBwuAUoKZeSLGpYiQt/9Cj99sZhrb60FjJf5vnnXO7rKhMHdSBH4DRzOBCJ2PeH0dnyLt1lzC3K5oiFyW6H2RjmEmThGDXiW6qKfBk3Aw6iRkuSQ1BddGXKWd0SqIsZe7j1efjMNncrrZ7DRyonZNsw1q9TTeDNYczkCJfvGwkX0N4OKxlk+zffF0Akod3bOJXoCBylPapafOt9Cddesn9kRtg/0+MMQ9Oqbm9P6gdwlGihbsxvposOyl4q6+EFD7YdStuluYJfspf+mu9xYOZ/GBYsSJE5F0xexr843cwSxda/5YTwOjQ85cPFHnpaPPGo5cLpYWi0cG749GMqogmgt15pDrGoABFOWd6tQXx2MOKGlrl66bHg7XUjsi2qWoGDz1OSw==";
      };

      users.users.containeruser = {
        isNormalUser = true;
        group = "users";
        home = "/home/containeruser";
        extraGroups = [ "nixbld" ];
      };

      systemd.tmpfiles.rules = [
        "d /home/containeruser 0755 containeruser users - -"
        "d /var/lib/github-runner/work 0755 containeruser users - -"
        "d ${nixenvGcRootsDir} 0755 containeruser users - -"
      ]
      ++ (surmaRepos |> map (name: "d /var/lib/github-runner/work/${name} 0755 containeruser users - -"));

      services.github-runners =
        surmaRepos
        |> map (name: {
          inherit name;
          value = {
            enable = true;
            url = "https://github.com/surma/${name}";
            tokenFile = "/var/lib/credentials/github-runner/token";
            name = "nexus-${name}-nix-x64";
            replace = true;
            runnerGroup = "Default";
            user = "containeruser";
            group = "users";
            workDir = "/var/lib/github-runner/work/${name}";
            extraLabels = [
              "nix"
              "nixos"
              "nexus"
              "container"
              "x64"
              name
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
              openssh
              zstd
            ];
            serviceOverrides = {
              StateDirectory = [ "github-runner/${name}" ];
              RuntimeDirectory = [ "github-runner/${name}" ];
              LogsDirectory = [ "github-runner/${name}" ];
              ProtectHome = false;
              PrivateUsers = false;
              PrivateMounts = false;
              Restart = lib.mkForce "on-failure";
              RestartSec = lib.mkForce "15s";
            }
            // (
              if name == "nixenv" then
                { ReadWritePaths = [ nixenvGcRootsDir ]; }
              else
                { InaccessiblePaths = [ "-${repoKeyPath}" ]; }
            );
          };
        })
        |> lib.listToAttrs;
    };
  };
}
