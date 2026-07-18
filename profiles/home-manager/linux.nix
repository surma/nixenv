{
  config,
  pkgs,
  lib,
  ...
}:
{
  home.username = lib.mkDefault "surma";
  home.homeDirectory = lib.mkDefault "/home/surma";
  home.packages = with pkgs; [
    wl-clipboard
  ];
  services.ssh-agent.enable = true;

  programs.ssh.settings = {
    "gitea.surma.technology" = {
      HostName = "gitea.surma.technology";
      Port = 2222;
      User = "containeruser";
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_surma";
      IdentityAgent = "/run/user/%i/ssh-agent";
    };

    "gitea-brain" = {
      HostName = "gitea.surma.technology";
      Port = 2222;
      User = "containeruser";
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_machine";
      IdentityAgent = "none";
    };
  };
}
