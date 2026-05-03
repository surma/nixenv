{ pkgs, inputs, ... }:
let
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
      HostName gitea.nexus.hosts.10.0.0.2.nip.io
      IdentityFile ${stateDir}/.ssh/id_repo_scout
      HostKeyAlias gitea.nexus.hosts.10.0.0.2.nip.io
      StrictHostKeyChecking accept-new

    Host gitea.nexus.hosts.10.0.0.2.nip.io
      Port 2222
      IdentitiesOnly yes
      User containeruser
      HostName gitea.nexus.hosts.10.0.0.2.nip.io
      IdentityFile ${stateDir}/.ssh/id_repo_scout
      StrictHostKeyChecking accept-new

    Host pylon
      HostName surmedge.hosts.surma.link
      User root
      IdentitiesOnly yes
      IdentityFile ${stateDir}/.ssh/id_deploy
      StrictHostKeyChecking accept-new

    Host citadel
      HostName 10.0.0.32
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
    host = "localhost";
    expose.port = port;
  };
}
