{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  ips = import ../../ips.nix;
  scoutApiPort = 32445;

  # Hook scripts for Scout topic lifecycle. Copied into the Nix store
  # so they're available at a stable path for SCOUT_HOOKS_DIR.
  scoutHooksDir = pkgs.runCommand "scout-hooks" { } ''
    mkdir -p $out
    cp ${../../assets/scout-hooks/topic-create} $out/topic-create
    cp ${../../assets/scout-hooks/topic-close} $out/topic-close
    chmod +x $out/topic-create $out/topic-close
  '';
in
{
  secrets.items.ssh-keys.command = ''
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet dump.mount; then
      cat > /dev/null
      exit 0
    fi

    mkdir -p /dump/state/scout/.ssh
    chown surma:users /dump/state/scout/.ssh
    chmod 0700 /dump/state/scout/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_surma.pub} /dump/state/scout/.ssh/id_surma.pub
    cat > /dump/state/scout/.ssh/id_surma
    echo >> /dump/state/scout/.ssh/id_surma
    chown surma:users /dump/state/scout/.ssh/id_surma.pub /dump/state/scout/.ssh/id_surma
    chmod 0600 /dump/state/scout/.ssh/id_surma
  '';

  secrets.items.scout-repo-ssh-key.command = ''
    key="$(cat)"

    # NixOS Admin service (HOME=/var/lib/nixos-admin)
    mkdir -p /var/lib/nixos-admin/.ssh
    chmod 0700 /var/lib/nixos-admin/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} /var/lib/nixos-admin/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > /var/lib/nixos-admin/.ssh/id_repo_scout
    chmod 0600 /var/lib/nixos-admin/.ssh/id_repo_scout

    # GitHub runner container, nixenv runner only (bind-mounted as
    # /var/lib/credentials/github-runner inside the container). The
    # containeruser UID is surma's UID.
    mkdir -p /var/lib/github-runner
    install -m 0600 -o surma -g users /dev/null /var/lib/github-runner/id_repo_scout
    printf '%s\n' "$key" > /var/lib/github-runner/id_repo_scout

    # The dependent containers remain stopped when /dump is unavailable.
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet dump.mount; then
      exit 0
    fi

    # Scout container (bind-mounted as /home/containeruser/.ssh inside the container)
    mkdir -p /dump/state/scout/.ssh
    chown surma:users /dump/state/scout/.ssh
    chmod 0700 /dump/state/scout/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} /dump/state/scout/.ssh/id_repo_scout.pub
    chown surma:users /dump/state/scout/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > /dump/state/scout/.ssh/id_repo_scout
    chown surma:users /dump/state/scout/.ssh/id_repo_scout
    chmod 0600 /dump/state/scout/.ssh/id_repo_scout

    # Brain serve container
    mkdir -p /dump/state/brain-serve/.ssh
    chown surma:users /dump/state/brain-serve/.ssh
    chmod 0700 /dump/state/brain-serve/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} /dump/state/brain-serve/.ssh/id_repo_scout.pub
    chown surma:users /dump/state/brain-serve/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > /dump/state/brain-serve/.ssh/id_repo_scout
    chown surma:users /dump/state/brain-serve/.ssh/id_repo_scout
    chmod 0600 /dump/state/brain-serve/.ssh/id_repo_scout
  '';

  # Read stdin once, then write both consumers: the Scout container key
  # (existing contract) and the LLM receiver's credential copy
  # (auth-rework section 6.5). No competing target declarations.
  secrets.items.llm-proxy-client-key.command = ''
    mkdir -p /var/lib/scout /var/lib/llm-proxy-credentials
    chown root:root /var/lib/llm-proxy-credentials
    chmod 0755 /var/lib/llm-proxy-credentials
    key="$(cat)"
    printf '%s\n' "$key" > /var/lib/scout/llm-proxy-client-key
    chown root:root /var/lib/scout/llm-proxy-client-key
    chmod 0644 /var/lib/scout/llm-proxy-client-key
    printf '%s\n' "$key" > /var/lib/llm-proxy-credentials/client-key
    chown root:root /var/lib/llm-proxy-credentials/client-key
    chmod 0644 /var/lib/llm-proxy-credentials/client-key
  '';

  secrets.items.scout-gws-credentials.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/gws-credentials.json
    chmod 0644 /var/lib/scout/gws-credentials.json
  '';

  secrets.items.scout-lidarr-api-key.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/lidarr-api-key
    chown surma:users /var/lib/scout/lidarr-api-key
    chmod 0600 /var/lib/scout/lidarr-api-key
  '';

  secrets.items.scout-radarr-api-key.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/radarr-api-key
    chown surma:users /var/lib/scout/radarr-api-key
    chmod 0600 /var/lib/scout/radarr-api-key
  '';

  secrets.items.scout-sonarr-api-key.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/sonarr-api-key
    chown surma:users /var/lib/scout/sonarr-api-key
    chmod 0600 /var/lib/scout/sonarr-api-key
  '';

  secrets.items.scout-prowlarr-api-key.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/prowlarr-api-key
    chown surma:users /var/lib/scout/prowlarr-api-key
    chmod 0600 /var/lib/scout/prowlarr-api-key
  '';

  secrets.items.scout-navidrome-password.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/navidrome-password
    chown surma:users /var/lib/scout/navidrome-password
    chmod 0600 /var/lib/scout/navidrome-password
  '';

  secrets.items.scout-spotify-credentials.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/spotify-credentials.json
    chown surma:users /var/lib/scout/spotify-credentials.json
    chmod 0600 /var/lib/scout/spotify-credentials.json
  '';

  secrets.items.scout-spotify-client-token.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/spotify-client-token.json
    chown surma:users /var/lib/scout/spotify-client-token.json
    chmod 0600 /var/lib/scout/spotify-client-token.json
  '';

  secrets.items.scout-cloudflare-api-token.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/cloudflare-api-token
    chown surma:users /var/lib/scout/cloudflare-api-token
    chmod 0600 /var/lib/scout/cloudflare-api-token
  '';

  # Password of the @scout Matrix account. Scout reads it for the first login
  # and for the cross-signing setup.
  secrets.items.scout-matrix-password.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/matrix-password
    chown surma:users /var/lib/scout/matrix-password
    chmod 0600 /var/lib/scout/matrix-password
  '';

  secrets.items.hetzner-cloud-api-token.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/hetzner-cloud-api-token
    chown surma:users /var/lib/scout/hetzner-cloud-api-token
    chmod 0600 /var/lib/scout/hetzner-cloud-api-token
  '';

  # Preserve the Scout copy (surma:users, 0600) and add the LLM
  # receiver's root-owned credential copy (auth-rework section 6.5).
  secrets.items.openrouter-api-key.command = ''
    mkdir -p /var/lib/scout /var/lib/llm-proxy-credentials
    chown root:root /var/lib/llm-proxy-credentials
    chmod 0755 /var/lib/llm-proxy-credentials
    key="$(cat)"
    printf '%s\n' "$key" > /var/lib/scout/openrouter-api-key
    chown surma:users /var/lib/scout/openrouter-api-key
    chmod 0600 /var/lib/scout/openrouter-api-key
    printf '%s\n' "$key" > /var/lib/llm-proxy-credentials/openrouter-key
    chown root:root /var/lib/llm-proxy-credentials/openrouter-key
    chmod 0644 /var/lib/llm-proxy-credentials/openrouter-key
  '';

  secrets.items.scout-firefly-access-token.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/firefly-access-token
    chown surma:users /var/lib/scout/firefly-access-token
    chmod 0600 /var/lib/scout/firefly-access-token
  '';

  secrets.items.scout-netlify-token.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/netlify-token
    chown surma:users /var/lib/scout/netlify-token
    chmod 0600 /var/lib/scout/netlify-token
  '';

  # Application key for the Philips Hue bridge. Home Assistant uses the
  # same key, so Scout can edit scenes and switch setups on the bridge.
  secrets.items.scout-hue-api-key.command = ''
    mkdir -p /var/lib/scout
    cat > /var/lib/scout/hue-api-key
    chown surma:users /var/lib/scout/hue-api-key
    chmod 0600 /var/lib/scout/hue-api-key
  '';

  secrets.items.scout-rmapi-config.command = ''
    mkdir -p /var/lib/scout/rmapi
    cat > /var/lib/scout/rmapi/rmapi.conf
    chown surma:users /var/lib/scout/rmapi /var/lib/scout/rmapi/rmapi.conf
    chmod 0700 /var/lib/scout/rmapi
    chmod 0600 /var/lib/scout/rmapi/rmapi.conf
  '';

  systemd.tmpfiles.rules = [
    "d- /dump/state/scout 0755 surma users - -"
  ];

  services.surmhosting.services.scout.backend."nixos-container".service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    serviceConfig.MemoryMax = "16G";
  };

  services.surmhosting.services.scout.backend."nixos-container" = {
    config = {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        # Module that wires the scout systemd service, with access to the
        # container's evaluated config (needed to reference the wrapped
        # pi package produced by home-manager).
        (
          { config, ... }:
          {
            systemd.services.scout =
              let
                pi = config.home-manager.users.containeruser.programs.pi.package;
              in
              {
                description = "Scout Matrix bridge";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" ];
                requires = [ "home-manager-containeruser.service" ];
                after = [
                  "network-online.target"
                  "home-manager-containeruser.service"
                ];
                path = [
                  # home-manager.useUserPackages puts the user environment here
                  # rather than in ~/.nix-profile. The hosting module enables this.
                  "/etc/profiles/per-user/containeruser"
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.git
                  pkgs.nix
                  pkgs.nodejs_24
                  pkgs.openssh
                  pkgs.procps
                  pkgs.sqlite
                  pkgs.zellij
                ];
                environment = {
                  SCOUT_PI_COMMAND = "${pi}/bin/pi";
                  SCOUT_CWD_TEMPLATE = "/home/containeruser/.local/state/scout/topics/{topic_id}";
                  SCOUT_API_PORT = toString scoutApiPort;
                  SCOUT_STATE_DIR = "/home/containeruser/.local/state/scout";
                  SCOUT_HOOKS_DIR = "${scoutHooksDir}";
                  SCOUT_LOG = "scout=debug";
                  # Scout talks to Surma through the Matrix homeserver on
                  # Nexus. The default model lives in Scout's state.db; set it
                  # with `!model default` in the "Scout status" room.
                  # The homeserver URL uses the internal Traefik entrypoint,
                  # so traffic stays on Nexus.
                  SCOUT_MATRIX_HOMESERVER = "http://matrix.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081";
                  SCOUT_MATRIX_USER = "@scout:matrix.surma.technology";
                  SCOUT_MATRIX_PASSWORD_FILE = "/var/lib/credentials/scout/matrix-password";
                  SCOUT_MATRIX_ALLOWED_USERS = "@surma:matrix.surma.technology";
                  # The "Scout" Space. Scout acts only in rooms of this Space.
                  SCOUT_MATRIX_SPACE = "!vy1niBPRrx4gqowId1:matrix.surma.technology";
                };
                serviceConfig = {
                  User = "containeruser";
                  Group = "users";
                  WorkingDirectory = "/home/containeruser";
                  Restart = "always";
                  RestartSec = 5;
                  ExecStart = pkgs.writeShellScript "scout-start" ''
                    PI_CONFIG_DIR="$HOME/.pi/agent/git/github.com/surma/pi-config"
                    if [ -d "$PI_CONFIG_DIR/.git" ]; then
                      ${pkgs.git}/bin/git -C "$PI_CONFIG_DIR" pull --ff-only
                    fi
                    exec ${inputs.scout.packages.${system}.scout}/bin/scout
                  '';
                };
              };

            # Weekly cleanup of retired topic workspaces.
            # Scout writes a .retired marker into topic directories on close;
            # this timer removes those directories after they've sat for 7+ days.
            systemd.services.scout-cleanup = {
              description = "Remove retired Scout topic workspaces";
              serviceConfig = {
                Type = "oneshot";
                User = "containeruser";
                Group = "users";
                ExecStart = pkgs.writeShellScript "scout-cleanup" ''
                  ${pkgs.findutils}/bin/find /home/containeruser/.local/state/scout/topics \
                    -maxdepth 2 -name .retired -mtime +7 -printf '%h\n' \
                  | while read -r dir; do
                      echo "removing retired workspace: $dir"
                      rm -rf "$dir"
                    done
                '';
              };
            };
            systemd.timers.scout-cleanup = {
              description = "Weekly cleanup of retired Scout topic workspaces";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "weekly";
                Persistent = true;
                RandomizedDelaySec = "1h";
              };
            };
            # Periodic brain sync on the main clone.
            # Keeps documents and the SQLite index/embeddings fresh so new
            # topic worktrees start with an up-to-date DB copy.
            systemd.services.brain-sync = {
              description = "Sync Brain knowledge base (main clone)";
              path = [
                pkgs.git
                pkgs.openssh
              ];
              serviceConfig = {
                Type = "oneshot";
                User = "containeruser";
                Group = "users";
                Environment = "BRAIN_PATH=/home/containeruser/.local/state/brain";
                ExecStart = "${inputs.brain.packages.${system}.default}/bin/brain sync";
              };
            };
            systemd.timers.brain-sync = {
              description = "Hourly Brain knowledge base sync";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "hourly";
                Persistent = true;
                RandomizedDelaySec = "5m";
              };
            };
          }
        )
      ];
      system.stateVersion = "25.05";

      hardware.graphics.enable = true;

      users.users.containeruser = {
        isNormalUser = true;
        group = "users";
        home = "/home/containeruser";
      };

      systemd.tmpfiles.rules = [
        "d /home/containeruser 0755 containeruser users - -"
      ];

      home-manager = {
        useGlobalPkgs = true;
        # useUserPackages defaults to true through the hosting module.
        sharedModules = [
          ../../modules/features/secrets.nix
          ../../modules/home-manager/agent
          ../../modules/home-manager/brain
          ../../modules/programs/web-search-cli
          ../../modules/programs/agent-browser
          ../../modules/programs/pi
          ../../modules/programs/surma-noti
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
          systemManager = "home-manager";
        };
        users.containeruser = import ../scout;
      };
    };

    allowedDevices = [
      {
        modifier = "rw";
        node = "/dev/dri/renderD128";
      }
      {
        modifier = "rw";
        node = "/dev/dri/card0";
      }
      # KVM acceleration for QEMU guests.
      {
        modifier = "rw";
        node = "/dev/kvm";
      }
    ];

    bindMounts = {
      home = {
        mountPoint = "/home/containeruser";
        hostPath = "/dump/state/scout";
        isReadOnly = false;
      };
      creds = {
        mountPoint = "/var/lib/credentials/scout";
        hostPath = "/var/lib/scout";
        isReadOnly = true;
      };
      dri = {
        mountPoint = "/dev/dri";
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      kvm = {
        mountPoint = "/dev/kvm";
        hostPath = "/dev/kvm";
        isReadOnly = false;
      };
      dump = {
        mountPoint = "/dump";
        hostPath = "/dump";
        isReadOnly = true;
      };
      scout-static = {
        mountPoint = "/home/containeruser/scout-static";
        hostPath = "/dump/state/scout-static";
        isReadOnly = false;
      };
      # Shared document folders — read-write overlays on top of the
      # read-only /dump mount so Scout can manage files in them. Nextcloud
      # surfaces the same trees as external storage.
      shared-audiobooks = {
        mountPoint = "/dump/audiobooks";
        hostPath = "/dump/audiobooks";
        isReadOnly = false;
      };
      shared-ebooks = {
        mountPoint = "/dump/ebooks";
        hostPath = "/dump/ebooks";
        isReadOnly = false;
      };
      shared-scratch = {
        mountPoint = "/dump/scratch";
        hostPath = "/dump/scratch";
        isReadOnly = false;
      };
      shared-surmvault = {
        mountPoint = "/dump/surmvault";
        hostPath = "/dump/surmvault";
        isReadOnly = false;
      };
      qbittorrent-downloads = {
        mountPoint = "/dump/state/qbittorrent/qBittorrent/downloads";
        hostPath = "/dump/state/qbittorrent/qBittorrent/downloads";
        isReadOnly = false;
      };
      lidarr-state = {
        mountPoint = "/dump/state/lidarr";
        hostPath = "/dump/state/lidarr";
        isReadOnly = false;
      };
    };
  };
}
