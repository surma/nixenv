{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/ai.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/linger.nix
  ];

  secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";
  secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    picocom
    tio
  ];

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  defaultConfigs.pi.extensions.proxy.enable = true;
}
