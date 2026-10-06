{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  scoutContainer = import ./scout-container.nix { inherit pkgs inputs; };
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
  '';

  # The shared deploy key of surma/brain, for the Scout container (Brain
  # sync, see modules/home-manager/brain) and the brain-serve container.
  secrets.items.brain-deploy-key.command = ''
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet dump.mount; then
      cat > /dev/null
      exit 0
    fi
    key="$(cat)"

    for home in /dump/state/scout /dump/state/brain-serve; do
      mkdir -p $home/.ssh
      chown surma:users $home/.ssh
      chmod 0700 $home/.ssh
      install -m 0644 -o surma -g users ${../../assets/ssh-keys/id_brain.pub} $home/.ssh/id_brain.pub
      install -m 0600 -o surma -g users /dev/null $home/.ssh/id_brain
      printf '%s\n' "$key" > $home/.ssh/id_brain
    done
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

  services.surmhosting.services.scout.backend."nixos-container" = scoutContainer {
    scout = inputs.scout.packages.${system}.scout;
    homeHostPath = "/dump/state/scout";
    matrixUser = "@scout:matrix.surma.technology";
    matrixPasswordFile = "/var/lib/credentials/scout/matrix-password";
    # The "Scout" Space.
    matrixSpace = "!vy1niBPRrx4gqowId1:matrix.surma.technology";
    memoryMax = "16G";

    # Voice calls (Element Call) in topic rooms.
    extraEnvironment.SCOUT_MATRIX_VOICE_CALL_COMMAND = "scout-voice-call";

    extraAllowedDevices = [
      # KVM acceleration for QEMU guests.
      {
        modifier = "rw";
        node = "/dev/kvm";
      }
    ];

    extraBindMounts = {
      kvm = {
        mountPoint = "/dev/kvm";
        hostPath = "/dev/kvm";
        isReadOnly = false;
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
