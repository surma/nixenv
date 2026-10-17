{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  ips = import ../../ips.nix;
  port = 8092;
  stateDir = "/var/lib/nixos-admin";

  # SSH config for git+ssh:// flake inputs and remote deploys.
  # Repo key is populated by the scout-repo-ssh-key secret.
  # Deploy key is populated by the nixos-admin-deploy-key secret.
  sshConfig = pkgs.writeText "nixos-admin-ssh-config" ''
    Host github.com
      IdentitiesOnly yes
      User git
      HostName github.com
      IdentityFile ${stateDir}/.ssh/id_repo_scout
      StrictHostKeyChecking accept-new

    Host gitea.surma.technology
      Port 2222
      IdentitiesOnly yes
      User containeruser
      HostName gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      IdentityFile ${stateDir}/.ssh/id_repo_scout
      HostKeyAlias gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      StrictHostKeyChecking accept-new

    Host gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      Port 2222
      IdentitiesOnly yes
      User containeruser
      HostName gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io
      IdentityFile ${stateDir}/.ssh/id_repo_scout
      StrictHostKeyChecking accept-new

    Host pylon
      HostName surmedge.hosts.surma.link
      User root
      IdentitiesOnly yes
      IdentityFile ${stateDir}/.ssh/id_deploy
      StrictHostKeyChecking accept-new

    Host citadel
      HostName ${ips.hosts.citadel.ip}
      User root
      IdentitiesOnly yes
      IdentityFile ${stateDir}/.ssh/id_deploy
      StrictHostKeyChecking accept-new

    # Explicit, so the known hosts are found also when ssh runs with
    # `-F <this file>` (nixos-admin's GIT_SSH_COMMAND) and not via HOME.
    Host *
      UserKnownHostsFile ${stateDir}/.ssh/known_hosts
  '';

  knownHosts = pkgs.writeText "nixos-admin-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
  '';
in
{
  imports = [
    inputs.nixos-admin-web.nixosModules.default
  ];

  services.nixos-admin = {
    enable = true;
    package = inputs.nixos-admin-web.packages.${pkgs.stdenv.hostPlatform.system}.default;
    listenAddress = "127.0.0.1:${toString port}";
    # git+ssh (key id_repo_scout, see sshConfig) instead of github:, so
    # deploys keep working when the repo is private. Deploy requests pin a
    # commit with git+ssh://git@github.com/surma/nixenv?rev=<sha>#nexus.
    flakeURL = "git+ssh://git@github.com/surma/nixenv?ref=main#nexus";
    sshConfigFile = "${stateDir}/.ssh/config";
    # App deploys (nexus.apps, modules/services/nexus-apps): nixos-admin
    # builds each app's flake into its per-app profile.
    appsConfigFile = config.nexus.appsAdminConfigFile;
  };

  # App deploys default to `deployOn = "push"`: a push to the tracked branch
  # deploys its head (merges to main are already CI-gated), so nixos-admin
  # needs no forge token. Forge API only for apps that opt into
  # `deployOn = "ci"`: Gitea through the internal entrypoint (no login;
  # nixos-admin runs on the host). GitHub: public API, no token, so a
  # private GitHub app repo with `deployOn = "ci"` needs a forge token file.
  nexus.appsForges.gitea.api = "http://gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081/api/v1";

  # Overlay: SSH key + config deployment for git+ssh:// flake inputs.
  systemd.services.nixos-admin = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    preStart = ''
      mkdir -p ${stateDir}/.ssh
      chmod 0700 ${stateDir}/.ssh
      install -m 0600 ${sshConfig} ${stateDir}/.ssh/config
      install -m 0644 ${knownHosts} ${stateDir}/.ssh/known_hosts
    '';
  };

  # Deploy key for remote NixOS deploys (machine-to-machine SSH).
  secrets.items.nixos-admin-deploy-key.command = ''
    key="$(cat)"

    mkdir -p ${stateDir}/.ssh
    chmod 0700 ${stateDir}/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_deploy.pub} ${stateDir}/.ssh/id_deploy.pub
    printf '%s\n' "$key" > ${stateDir}/.ssh/id_deploy
    chmod 0600 ${stateDir}/.ssh/id_deploy
  '';

  services.surmhosting.services.admin = {
    backend.host = "localhost";
    expose.apps.admin = {
      access.mode = "allowlist";
      access.seedUsers = [ "surma" ];
      internal.access = "trusted-network";
      ports = [
        {
          port = port;
          hostname = "admin";
        }
      ];
    };
    # Forge webhooks for app deploys, without the login: GitHub posts to
    # https://admin-hooks.apps.surma.technology/hooks/github. Only /hooks/
    # is routed; a hook only makes nixos-admin re-check the forge, so it
    # needs no secret (nixos-admin-web README, "Webhooks"). Gitea uses the
    # internal entrypoint instead (service-gitea.nix).
    expose.apps.admin-hooks = {
      access.mode = "public";
      internal.enable = false;
      ports = [
        {
          port = port;
          hostname = "admin-hooks";
          publicPathPrefixes = [ "/hooks/" ];
        }
      ];
    };
  };

  # Citadel's nixos-admin (it deploys citadel and pylon), reachable from
  # outside through nexus, behind the same surm-auth login as nexus's admin.
  # Citadel listens on :${toString port} (machines/citadel/service-nixos-admin.nix).
  services.surmhosting.services.admin-citadel = {
    backend.host = ips.hosts.citadel.ip;
    expose.apps.admin-citadel = {
      access.mode = "allowlist";
      access.seedUsers = [ "surma" ];
      internal.access = "trusted-network";
      ports = [
        {
          port = port;
          hostname = "admin-citadel";
        }
      ];
    };
  };
}
