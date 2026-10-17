{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  ips = import ../../ips.nix;
  brainPkg = inputs.brain.packages.${system}.default;
  brainRepoUrl = "ssh://containeruser@gitea.surma.technology:2222/surma/brain.git";
  brainPath = "/var/lib/brain-serve/brain";

  sshConfig = pkgs.writeText "brain-serve-ssh-config" ''
    Host gitea.surma.technology
      Hostname ${ips.hosts.nexus.ip}
      Port 2222
      User containeruser
      IdentityFile /var/lib/brain-serve/.ssh/id_brain
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      HostKeyAlias gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      UserKnownHostsFile /var/lib/brain-serve/.ssh/known_hosts
  '';

  gitSshCommand = "ssh -F ${sshConfig}";

  llmApiKeyFile = "/var/lib/credentials/llm-proxy-client-key";
  llmEndpoint = "https://proxy.llm.surma.technology/v1";
  llmModel = "shopify:anthropic:claude-haiku-4-5";
  publicUrl = "https://public-brain.surma.technology";

  shareRuntimeDir = "/run/brain-serve";
  shareKeyDir = "${shareRuntimeDir}/jwt";
  sharePrivateKeyFile = "${shareKeyDir}/private.pem";
  sharePublicKeyFile = "${shareKeyDir}/public.pem";

  generateShareKeys = pkgs.writeShellScript "brain-serve-generate-share-keys" ''
    set -euo pipefail
    umask 077

    if [ -s "${sharePrivateKeyFile}" ] && [ -s "${sharePublicKeyFile}" ]; then
      exit 0
    fi
    if [ -e "${shareKeyDir}" ]; then
      echo "Share-key directory exists but does not contain a complete key pair" >&2
      exit 1
    fi

    tmpDir="$(${pkgs.coreutils}/bin/mktemp -d "${shareKeyDir}.tmp.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -rf "$tmpDir"' EXIT
    ${pkgs.openssl}/bin/openssl genpkey -algorithm Ed25519 -out "$tmpDir/private.pem"
    ${pkgs.openssl}/bin/openssl pkey -in "$tmpDir/private.pem" -pubout -out "$tmpDir/public.pem"
    ${pkgs.coreutils}/bin/mv "$tmpDir" "${shareKeyDir}"
    trap - EXIT
  '';

  waitForShareKeys = pkgs.writeShellScript "brain-serve-wait-for-share-keys" ''
    set -euo pipefail
    for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
      if [ -r "${sharePrivateKeyFile}" ] && [ -r "${sharePublicKeyFile}" ]; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "Timed out waiting for Brain share keys" >&2
    exit 1
  '';

  brainSync = pkgs.writeShellScript "brain-serve-sync" ''
    set -euo pipefail
    export GIT_SSH_COMMAND="${gitSshCommand}"
    export NO_COLOR=1
    if [ ! -d "${brainPath}/.git" ]; then
      echo "Cloning brain repository..."
      rm -rf "${brainPath}"
      ${pkgs.git}/bin/git clone ${brainRepoUrl} ${brainPath}
    fi

    # brain-serve owns its checkout: it may hold local commits (failed
    # push/rebase) and written-but-unsynced files from the write API, so
    # never reset it. Only clean up a stale rebase; `brain sync` does the
    # fetch, rebase (semantic merge driver) and push.
    ${pkgs.git}/bin/git -C ${brainPath} rebase --abort 2>/dev/null || true

    echo "Running brain sync..."
    BRAIN_PATH=${brainPath} ${brainPkg}/bin/brain sync
  '';

  # Hourly sync goes through the running server's sync queue, so the
  # server stays the only writer of its checkout and keeps the models.
  brainSyncViaServer = pkgs.writeShellScript "brain-serve-update" ''
    set -euo pipefail
    echo "POST http://localhost:8080/api/sync"
    ${pkgs.curl}/bin/curl -sS --fail-with-body --max-time 900 \
      -X POST http://localhost:8080/api/sync
    echo
  '';

  brainServeStart = pkgs.writeShellScript "brain-serve-start" ''
    set -euo pipefail
    export NO_COLOR=1
    LLM_FLAGS=""
    if [ -f "${llmApiKeyFile}" ]; then
      LLM_KEY="$(cat "${llmApiKeyFile}")"
      LLM_FLAGS="--llm-endpoint ${llmEndpoint} --llm-api-key $LLM_KEY --llm-model ${llmModel}"
    fi
    exec ${brainPkg}/bin/brain serve \
      --port 8080 \
      --jwt-private-key-file "${sharePrivateKeyFile}" \
      --public-url "${publicUrl}" \
      $LLM_FLAGS
  '';

  brainServePublicStart = pkgs.writeShellScript "brain-serve-public-start" ''
    set -euo pipefail
    export NO_COLOR=1
    exec ${brainPkg}/bin/brain serve \
      --port 8081 \
      --public \
      --jwt-public-key-file "${sharePublicKeyFile}"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d- /dump/state/brain-serve 0755 surma users - -"
  ];

  services.surmhosting.services.brain-serve.backend."nixos-container".service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    # QMD model loading needs ~4GB; give headroom for the server + sync.
    serviceConfig.MemoryMax = "8G";
  };

  # Brain runs two servers with separate policies: private (8080,
  # allowlist) and public (8081, public). They are different logical
  # apps and must never share a grant (auth-rework section 4.3).
  services.surmhosting.services.brain-serve.expose.apps.brain = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    public.aliases = [ "brain.surma.technology" ];
    ports = [
      {
        port = 8080;
        hostname = "brain-serve";
      }
    ];
  };

  services.surmhosting.services.brain-serve.expose.apps.public-brain = {
    access.mode = "public";
    internal.access = "trusted-network";
    public.aliases = [ "public-brain.surma.technology" ];
    ports = [
      {
        port = 8081;
        hostname = "public-brain";
      }
    ];
  };
  services.surmhosting.services.brain-serve.backend."nixos-container" = {
    # GPU access for Vulkan-accelerated QMD inference (Intel iGPU).
    allowedDevices = [
      {
        modifier = "rw";
        node = "/dev/dri/renderD128";
      }
      {
        modifier = "rw";
        node = "/dev/dri/card1";
      }
    ];
    bindMounts.dri = {
      mountPoint = "/dev/dri";
      hostPath = "/dev/dri";
      isReadOnly = false;
    };

    config = {
      system.stateVersion = "25.05";

      # Vulkan drivers for Intel iGPU — needed by node-llama-cpp for
      # GPU-accelerated QMD inference.
      hardware.graphics.enable = true;
      hardware.graphics.extraPackages = [ pkgs.intel-compute-runtime ];
      environment.systemPackages = [ pkgs.vulkan-tools ];

      # brain-serve is NOT wantedBy multi-user.target — it's started by
      # a timer 10s after boot. This prevents the slow clone/sync from
      # blocking container boot and causing the host container unit to
      # time out during switch-to-configuration.
      systemd.services.brain-serve = {
        description = "Brain knowledge base web server";
        wants = [
          "network-online.target"
          "brain-serve-public.service"
        ];
        after = [ "network-online.target" ];
        path = [
          brainPkg
          pkgs.git
          pkgs.openssh
          pkgs.coreutils
          pkgs.openssl
        ];
        environment = {
          BRAIN_PATH = brainPath;
          GIT_SSH_COMMAND = gitSshCommand;
          HOME = "/var/lib/brain-serve";
          # QMD would size its parallel embedding/rerank contexts from the
          # iGPU's "free VRAM" (shared system RAM): up to 4 rerank contexts
          # of ~1 GB+ each, which OOM-killed the service on the first
          # semantic search. The server runs model work one job at a time,
          # so one context each is enough.
          BRAIN_QMD_MAX_CONTEXTS = "1";
          GIT_AUTHOR_NAME = "Surma";
          GIT_AUTHOR_EMAIL = "surma@surma.dev";
          GIT_COMMITTER_NAME = "Surma";
          GIT_COMMITTER_EMAIL = "surma@surma.dev";
        };
        serviceConfig = {
          # "-": a failing sync (conflict, Gitea down) is logged but does
          # not keep the server from starting.
          ExecStartPre = [
            "-${brainSync}"
            "${generateShareKeys}"
          ];
          ExecStart = "${brainServeStart}";
          RuntimeDirectory = "brain-serve";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "no";
          User = "containeruser";
          Restart = "always";
          RestartSec = 30;
          TimeoutStartSec = 900;
        };
      };

      # Public brain-serve: read-only, serves only public: true docs.
      # BindsTo brain-serve so it starts/stops together with it.
      # brain-serve is timer-activated (not WantedBy multi-user.target),
      # so this unit must be pulled in via Wants on brain-serve.
      systemd.services.brain-serve-public = {
        description = "Brain public web server";
        bindsTo = [ "brain-serve.service" ];
        after = [ "brain-serve.service" ];
        path = [
          brainPkg
          pkgs.coreutils
        ];
        environment = {
          BRAIN_PATH = brainPath;
          HOME = "/var/lib/brain-serve";
        };
        serviceConfig = {
          ExecStartPre = "${waitForShareKeys}";
          ExecStart = "${brainServePublicStart}";
          User = "containeruser";
          Restart = "always";
          RestartSec = 10;
        };
      };

      # Start brain-serve 10s after boot, giving the container network
      # time to come up without blocking the boot sequence.
      systemd.timers.brain-serve = {
        description = "Delayed start for brain-serve";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10s";
        };
      };

      systemd.services.brain-serve-update = {
        description = "Sync brain repository via brain-serve POST /api/sync";
        serviceConfig = {
          Type = "oneshot";
          User = "containeruser";
          ExecStart = "${brainSyncViaServer}";
          TimeoutStartSec = 900;
        };
      };

      systemd.timers.brain-serve-update = {
        description = "Hourly brain sync via brain-serve";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };
    };

    bindMounts.state = {
      mountPoint = "/var/lib/brain-serve";
      hostPath = "/dump/state/brain-serve";
      isReadOnly = false;
    };

    # Bind-mount the LLM proxy client key (provisioned by the host
    # secrets service) into the container read-only.
    bindMounts.llm-key = {
      mountPoint = "/var/lib/credentials";
      hostPath = "/var/lib/scout";
      isReadOnly = true;
    };
  };
}
