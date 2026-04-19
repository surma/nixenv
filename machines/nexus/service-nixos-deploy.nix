{ pkgs, ... }:
let
  port = 8092;
  deployStateDir = "/var/lib/nixos-deploy";

  # SSH config for git+ssh:// flake inputs (private repos on GitHub and Gitea).
  # The key is populated by the secrets service into $deployStateDir/.ssh/.
  sshConfig = pkgs.writeText "nixos-deploy-ssh-config" ''
    Host github.com
      IdentitiesOnly yes
      User git
      HostName github.com
      IdentityFile ${deployStateDir}/.ssh/id_repo_scout
      StrictHostKeyChecking accept-new

    Host gitea.surma.technology
      Port 2222
      IdentitiesOnly yes
      User containeruser
      HostName gitea.nexus.hosts.10.0.0.2.nip.io
      IdentityFile ${deployStateDir}/.ssh/id_repo_scout
      HostKeyAlias gitea.nexus.hosts.10.0.0.2.nip.io
      StrictHostKeyChecking accept-new

    Host gitea.nexus.hosts.10.0.0.2.nip.io
      Port 2222
      IdentitiesOnly yes
      User containeruser
      HostName gitea.nexus.hosts.10.0.0.2.nip.io
      IdentityFile ${deployStateDir}/.ssh/id_repo_scout
      StrictHostKeyChecking accept-new
  '';

  knownHosts = pkgs.writeText "nixos-deploy-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
  '';
in
{
  imports = [
    ../../modules/services/nixos-deploy
  ];

  services.nixos-deploy = {
    enable = true;
    listenAddress = "127.0.0.1:${toString port}";
    flakeURL = "github:surma/nixenv#nexus";
  };

  # Overlay: add SSH support for git+ssh:// flake inputs.
  systemd.services.nixos-deploy = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    path = [ pkgs.openssh ];
    preStart = ''
      mkdir -p ${deployStateDir}/.ssh
      chmod 0700 ${deployStateDir}/.ssh
      install -m 0600 ${sshConfig} ${deployStateDir}/.ssh/config
      install -m 0644 ${knownHosts} ${deployStateDir}/.ssh/known_hosts
    '';
  };

  services.surmhosting.services.nixos-deploy = {
    host = "localhost";
    expose.port = port;
  };
}
