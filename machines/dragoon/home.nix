{
  config,
  pkgs,
  lib,
  ...
}:
let
  shared = import ../../modules/services/syncthing/common.nix { inherit lib pkgs; };
in
{
  imports = [
    # Program modules are auto-loaded from ../../modules/programs

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/physical.nix
    ../../profiles/home-manager/macos.nix
    ../../profiles/home-manager/experiments.nix
    ../../profiles/home-manager/cloud.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/ai.nix
    ../../profiles/home-manager/javascript.nix
    ../../profiles/home-manager/godot.nix
  ];

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmbook";
  defaultConfigs.agents.enable = true;

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
  defaultConfigs.pi.extensions.proxy.enable = true;
  defaultConfigs.helix.enableSlSyntax = true;
  programs.ghostty.enable = true;
  defaultConfigs.ghostty.enable = true;
  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;
  programs.obsidian.enable = true;

  programs.qmd.enable = true;

  programs.go.enable = true;

  customScripts.denix.enable = true;
  customScripts.noti.enable = true;
  customScripts.llm-proxy.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.ccp.enable = true;
  customScripts.wallpaper-shuffle.enable = true;
  customScripts.wallpaper-shuffle.asDesktopItem = true;
  customScripts.oc.enable = true;
  customScripts.ocq.enable = true;

  xdg.configFile = {
    "dump/config.json".text = builtins.toJSON { server = "http://10.0.0.2:8081"; };
  };

  secrets.items.dragoon-syncthing.target = "${config.home.homeDirectory}/.local/state/syncthing/key.pem";
  secrets.items.syncthing-relay-token.target = "${config.home.homeDirectory}/.local/state/syncthing-relay/token";

  services.syncthing.enable = true;
  services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
  services.syncthing.key = config.secrets.items.dragoon-syncthing.target;
  services.syncthing.settings.devices.arbiter = shared.devices.arbiter;
  services.syncthing.settings.folders."${config.home.homeDirectory}/SurmVault".devices = lib.mkForce [
    "nexus"
    "arbiter"
  ];
  defaultConfigs.syncthing.enable = true;
  defaultConfigs.syncthing.privateRelay.enable = true;
  defaultConfigs.syncthing.privateRelay.tokenFile = config.secrets.items.syncthing-relay-token.target;
  defaultConfigs.syncthing.knownFolders.scratch.enable = true;
  defaultConfigs.syncthing.knownFolders.ebooks.enable = true;
  defaultConfigs.syncthing.knownFolders.surmvault.enable = true;
  defaultConfigs.syncthing.knownFolders.surmvault.path = "${config.home.homeDirectory}/SurmVault";

}
