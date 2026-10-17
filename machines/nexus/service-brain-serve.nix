{ pkgs, lib, ... }:
let
  ips = import ../../ips.nix;
  appHome = "/var/lib/app";
  appStateDir = "/dump/state/brain-serve";
  brainPath = "${appHome}/brain";
  appProfile = "/nix/var/nix/profiles/app";
  brainBinary = "${appProfile}/bin/brain";
  brainRepoUrl = "ssh://containeruser@gitea.surma.technology:2222/surma/brain.git";

  sshConfig = pkgs.writeText "brain-serve-ssh-config" ''
    Host gitea.surma.technology
      Hostname ${ips.hosts.nexus.ip}
      Port 2222
      User containeruser
      IdentityFile ${appHome}/.ssh/id_brain
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      HostKeyAlias gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      UserKnownHostsFile ${appHome}/.ssh/known_hosts
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
      ${pkgs.coreutils}/bin/rm -rf "${brainPath}"
      ${pkgs.git}/bin/git clone ${brainRepoUrl} ${brainPath}
    fi

    # brain-serve owns its checkout: it may hold local commits (failed
    # push/rebase) and written-but-unsynced files from the write API, so
    # never reset it. Only clean up a stale rebase; `brain sync` does the
    # fetch, rebase (semantic merge driver) and push.
    ${pkgs.git}/bin/git -C ${brainPath} rebase --abort 2>/dev/null || true

    echo "Running brain sync..."
    BRAIN_PATH=${brainPath} ${brainBinary} sync
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
    args=(
      --port 8080
      --jwt-private-key-file "${sharePrivateKeyFile}"
      --public-url "${publicUrl}"
    )
    if [ -f "${llmApiKeyFile}" ]; then
      LLM_KEY="$(cat "${llmApiKeyFile}")"
      args+=(
        --llm-endpoint "${llmEndpoint}"
        --llm-api-key "$LLM_KEY"
        --llm-model "${llmModel}"
      )
    fi
    exec ${brainBinary} serve "''${args[@]}"
  '';

  brainServePublicStart = pkgs.writeShellScript "brain-serve-public-start" ''
    set -euo pipefail
    export NO_COLOR=1
    exec ${brainBinary} serve \
      --port 8081 \
      --public \
      --jwt-public-key-file "${sharePublicKeyFile}"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d- /dump/state/brain-serve 0755 surma users - -"
  ];

  nexus.apps.brain-serve = {
    # This is a private GitHub repo; use SSH for nixos-admin's app build,
    # while nexus.apps derives the webhook forge/repo below.
    flake = "git+ssh://git@github.com/surma/brain";
    ref = "main";
    package = "default";
    program = "brain";
    forge = "github";
    repo = "surma/brain";

    # Keep the existing checkout, QMD/SQLite data, and SSH identity in the
    # same host directory; nexus.apps mounts it at /var/lib/app.
    stateDir = appStateDir;

    env = {
      HOME = appHome;
      BRAIN_PATH = brainPath;
      GIT_SSH_COMMAND = gitSshCommand;
      # QMD would size its parallel embedding/rerank contexts from the
      # iGPU's "free VRAM" (shared system RAM): multiple contexts could
      # OOM-kill the service. Brain runs model work one job at a time.
      BRAIN_QMD_MAX_CONTEXTS = "1";
      # On this Intel ADL-N iGPU + 8 E-cores, expansion is faster on CPU,
      # reranking on GPU, and reranking only the best 6 candidates keeps
      # search latency manageable. Requests can still override this.
      BRAIN_QMD_EXPAND_ON_CPU = "1";
      BRAIN_QMD_RERANK = "6";
      BRAIN_QMD_RERANK_CHARS = "800";
      GIT_AUTHOR_NAME = "Surma";
      GIT_AUTHOR_EMAIL = "surma@surma.dev";
      GIT_COMMITTER_NAME = "Surma";
      GIT_COMMITTER_EMAIL = "surma@surma.dev";
    };

    containerConfig = { lib, ... }: {
      system.stateVersion = "25.05";

      # Vulkan drivers and /dev/dri access for Intel iGPU QMD inference.
      hardware.graphics.enable = true;
      hardware.graphics.extraPackages = [ pkgs.intel-compute-runtime ];
      environment.systemPackages = [ pkgs.vulkan-tools ];

      # The app profile supplies the executable, but app.service remains the
      # private server on 8080. The public server is a second process from
      # the same profile and follows app.service's lifecycle.
      systemd.services.app = {
        # Start 10 seconds after boot from app.timer, not during container
        # activation; nixos-admin can still restart it after profile flips.
        wantedBy = lib.mkForce [ ];
        wants = [ "brain-serve-public.service" ];
        serviceConfig = {
          ExecStartPre = [
            "-${brainSync}"
            "${generateShareKeys}"
          ];
          ExecStart = lib.mkForce "${brainServeStart}";
          RuntimeDirectory = "brain-serve";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "no";
          RestartSec = lib.mkForce "30s";
          TimeoutStartSec = 900;
        };
      };

      systemd.services.brain-serve-public = {
        description = "Brain public web server";
        bindsTo = [ "app.service" ];
        after = [ "app.service" ];
        environment = {
          BRAIN_PATH = brainPath;
          HOME = appHome;
        };
        serviceConfig = {
          ExecStartPre = "${waitForShareKeys}";
          ExecStart = "${brainServePublicStart}";
          User = "containeruser";
          Restart = "always";
          RestartSec = 10;
        };
      };

      # The service's timer delays its clone/sync until the container has
      # had 10 seconds to bring up networking. The app service itself is
      # still restartable by nixos-admin on a new profile.
      systemd.timers.app = {
        description = "Delayed start for Brain's private server";
        wantedBy = [ "timers.target" ];
        timerConfig.OnBootSec = "10s";
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

    expose = {
      # Keep the Sausage `brain` actor's API on the private server at
      # http://brain-serve.nexus.hosts.<nexus-ip>.nip.io:8081.
      apps.brain = {
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

      apps.public-brain = {
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
    };
  };

  # The host container unit still waits for the secrets service and keeps
  # the existing 8G cgroup limit. The iGPU device nodes are also attached
  # at the host/container boundary, as in the former standalone container.
  services.surmhosting.services.brain-serve.backend."nixos-container" = {
    service = {
      wants = [ "secrets.service" ];
      after = [ "secrets.service" ];
      # QMD model loading needs ~4GB; give headroom for server + sync.
      serviceConfig.MemoryMax = "8G";
    };
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
    # This backend freeform value is shallow-merged by surmhosting. Include
    # nexus.apps' persistent-state mount explicitly alongside the extra mounts,
    # or the DRI/credential bindings would replace it.
    bindMounts = {
      app-state = {
        mountPoint = appHome;
        hostPath = appStateDir;
        isReadOnly = false;
      };
      dri = {
        mountPoint = "/dev/dri";
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      llm-key = {
        mountPoint = "/var/lib/credentials";
        hostPath = "/var/lib/scout";
        isReadOnly = true;
      };
    };
  };
}
