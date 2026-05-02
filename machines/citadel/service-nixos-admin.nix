{ pkgs, inputs, lib, ... }:
let
  port = 8092;
  stateDir = "/var/lib/nixos-admin";

  # SSH config for git+ssh:// flake inputs (private repos on GitHub and Gitea).
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
    flakeURL = "github:surma/nixenv#citadel";
  };

  # Overlay: add SSH support for git+ssh:// flake inputs.
  systemd.services.nixos-admin = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    path = [ pkgs.openssh ];
    preStart = ''
      mkdir -p ${stateDir}/.ssh
      chmod 0700 ${stateDir}/.ssh
      install -m 0600 ${sshConfig} ${stateDir}/.ssh/config
      install -m 0644 ${knownHosts} ${stateDir}/.ssh/known_hosts
    '';
  };

  services.surmhosting.services.admin = {
    host = "localhost";
    expose.port = port;
  };

  # Deploy the SSH key for git+ssh:// flake inputs used by nixos-rebuild.
  secrets.items.scout-repo-ssh-key.command = ''
    key="$(cat)"

    mkdir -p ${stateDir}/.ssh
    chmod 0700 ${stateDir}/.ssh

    install -m 0644 ${../../assets/ssh-keys/id_repo_scout.pub} ${stateDir}/.ssh/id_repo_scout.pub
    printf '%s\n' "$key" > ${stateDir}/.ssh/id_repo_scout
    chmod 0600 ${stateDir}/.ssh/id_repo_scout
  '';
}
