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
}
