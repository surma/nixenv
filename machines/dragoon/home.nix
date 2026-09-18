{
  config,
  pkgs,
  lib,
  ...
}:
let
  ips = import ../../ips.nix;
  shared = import ../../modules/services/syncthing/common.nix { inherit lib pkgs; };
  ollama = pkgs.ollama.overrideAttrs (old: {
    postPatch =
      builtins.replaceStrings
        [ "rm model/models/nemotronh/model_omni_test.go" ]
        [ "rm -f model/models/nemotronh/model_omni_test.go" ]
        old.postPatch;
  });
in
{
  imports = [
    # Program modules are auto-loaded from ../../modules/programs

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/roles/dev.nix
    ../../profiles/home-manager/roles/workstation.nix
    ../../profiles/home-manager/gui/fonts.nix
    ../../profiles/home-manager/gui/terminal.nix
    ../../profiles/home-manager/gui/gui-apps.nix
    ../../profiles/home-manager/platform/physical.nix
    ../../profiles/home-manager/platform/macos.nix
    ../../profiles/home-manager/roles/cloud.nix
    ../../profiles/home-manager/roles/nixdev.nix
    ../../profiles/home-manager/roles/ai.nix
    ../../profiles/home-manager/roles/javascript.nix
    ../../profiles/home-manager/roles/go.nix
    ../../profiles/home-manager/roles/godot.nix
    ../../profiles/home-manager/services/syncthing-peer.nix
    ../../profiles/home-manager/services/syncthing-vault.nix
  ];

  home.stateVersion = "24.05";
  programs.gitea-cli.enable = true;

  agent.skills = [
    ../../assets/skills/herdr-orchestrator
  ];

  allowedUnfreeApps = [
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
      bun
    ]
  );

  defaultConfigs.pi.extensions.proxy.enable = true;
  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;
  programs.obsidian.enable = true;

  programs.qmd.enable = true;

  customScripts.denix.enable = true;
  programs.surma-noti.enable = true;
  customScripts.llm-proxy.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.ccp.enable = true;
  customScripts.wallpaper-shuffle.enable = true;
  customScripts.wallpaper-shuffle.asDesktopItem = true;
  customScripts.oc.enable = true;
  customScripts.ocq.enable = true;
  customScripts.transcribe.enable = true;

  xdg.configFile = {
    "dump/config.json".text = builtins.toJSON { server = "http://${ips.hosts.nexus.ip}:8123"; };
  };

  secrets.items.huggingface-token.target = "${config.home.homeDirectory}/.config/nixenv/huggingface-token";
  secrets.items.m-config.target = "${config.home.homeDirectory}/.config/m/config.yaml";
  services.syncthing.settings.devices.arbiter = shared.devices.arbiter;
  services.syncthing.settings.folders."${config.home.homeDirectory}/SurmVault".devices = lib.mkForce [
    "nexus"
    "arbiter"
  ];
}
