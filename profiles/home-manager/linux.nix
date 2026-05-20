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

  programs.ssh.matchBlocks = {
    "gitea.surma.technology" = {
      hostname = "gitea.surma.technology";
      port = 2222;
      user = "containeruser";
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_surma";
      extraOptions.IdentityAgent = "/run/user/%i/ssh-agent";
    };

    "gitea-brain" = {
      hostname = "gitea.surma.technology";
      port = 2222;
      user = "containeruser";
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_machine";
      extraOptions.IdentityAgent = "none";
    };
  };
}
