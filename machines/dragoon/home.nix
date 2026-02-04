{ config, pkgs, ... }:
{
  imports = [
    # Programs now globally injected
    # ../../modules/programs/telegram

    # Application modules now globally injected
    # Application modules now globally injected
    # ../../modules/home-manager/claude-code
    # ../../modules/home-manager/opencode
    # ../../modules/home-manager/ghostty
    # ../../modules/home-manager/handy
    # ../../modules/services/syncthing

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/physical.nix
    ../../profiles/home-manager/macos.nix
    ../../profiles/home-manager/experiments.nix
    ../../profiles/home-manager/cloud.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/javascript.nix
    ../../profiles/home-manager/godot.nix
  ];

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmbook";

  allowedUnfreeApps = [
    "claude-code"
    "obsidian"
  ];

  home.packages = (
    with pkgs;
    [
      openscad
      jqp
      ollama
      qbittorrent
      jupyter
      gopls
      bun
    ]
  );

  programs.telegram.enable = true;
  programs.claude-code.enable = true;
  defaultConfigs.claude-code.enable = true;
  programs.opencode.enable = true;
  defaultConfigs.opencode.enable = true;
  programs.pi.enable = true;
  programs.pi.extensions.plan-mode.enable = true;
  defaultConfigs.pi.enable = true;
  programs.ghostty.enable = true;
  defaultConfigs.ghostty.enable = true;
  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;
  programs.obsidian.enable = true;

  programs.go.enable = true;

  customScripts.denix.enable = true;
  customScripts.noti.enable = true;
  customScripts.llm-proxy.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.wallpaper-shuffle.enable = true;
  customScripts.wallpaper-shuffle.asDesktopItem = true;
  customScripts.oc.enable = true;
  customScripts.ocq.enable = true;

  xdg.configFile = {
    "dump/config.json".text = builtins.toJSON { server = "http://10.0.0.2:8081"; };
  };

  services.syncthing.enable = true;
  defaultConfigs.syncthing.enable = true;
  defaultConfigs.syncthing.knownFolders.scratch.enable = true;
  defaultConfigs.syncthing.knownFolders.ebooks.enable = true;

}
