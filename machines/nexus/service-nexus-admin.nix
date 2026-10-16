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

  # API token for the CI gate of app deploys on Gitea (the repos are
  # private): a Gitea token with read access to the app repos
  # (scope read:repository), stored age-encrypted as
  # secrets/nixos-admin-gitea-token.age (recipients: secrets/config.nix).
  # Until that file exists the secret item is skipped and Gitea apps with
  # `deployOn = "ci"` fail their forge lookups (logged by nixos-admin).
  giteaTokenSecret = ../../secrets/nixos-admin-gitea-token.age;
  giteaTokenFile = "${stateDir}/forge/gitea-token";

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
    flakeURL = "github:surma/nixenv#nexus";
    sshConfigFile = "${stateDir}/.ssh/config";
    # App deploys (nexus.apps, modules/services/nexus-apps): nixos-admin
    # builds each app's flake into its per-app profile.
    appsConfigFile = config.nexus.appsAdminConfigFile;
  };

  # Forge access for the CI gate. Gitea through the internal entrypoint
  # (no login; nixos-admin runs on the host). GitHub: public API, no token.
  nexus.appsForges.gitea = {
    api = "http://gitea.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081/api/v1";
    tokenFile = giteaTokenFile;
  };

  secrets.items.nixos-admin-gitea-token = lib.mkIf (builtins.pathExists giteaTokenSecret) {
    target = giteaTokenFile;
    mode = "0600";
  };

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
}
