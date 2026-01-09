{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../../profiles/darwin/base.nix

    ../../modules/programs/signal
    ../../modules/programs/obs
    ../../modules/programs/obsidian
  ];

  system.stateVersion = 5;
  networking.hostName = "dragoon";

  homebrew = {
    casks = [
      "nvidia-geforce-now"
      "magicavoxel"
    ];
  };

  ids.gids.nixbld = 30000;

  programs.signal.enable = true;
  programs.obs.enable = true;
  programs.obsidian.enable = true;

  home-manager.users.${config.system.primaryUser} =
    { config, ... }:
    {
      imports = [
        ../../modules/programs/telegram

        ../../modules/home-manager/claude-code
        ../../modules/home-manager/opencode
        ../../modules/home-manager/ghostty
        ../../modules/services/syncthing

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

      secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.config/llm-proxy/client-key";

      allowedUnfreeApps = [
        "claude-code"
      ];

      home.packages = (
        with pkgs;
        [
          openscad
          jqp
          ollama
          qbittorrent
          jupyter
        ]
      );

      programs.telegram.enable = true;
      programs.claude-code.enable = true;
      defaultConfigs.claude-code.enable = true;
      programs.opencode.enable = true;
      defaultConfigs.opencode.enable = true;
      programs.ghostty.enable = true;
      defaultConfigs.ghostty.enable = true;

      customScripts.denix.enable = true;
      customScripts.noti.enable = true;
      customScripts.llm-proxy.enable = true;
      customScripts.ghclone.enable = true;
      customScripts.wallpaper-shuffle.enable = true;
      customScripts.wallpaper-shuffle.asDesktopItem = true;

      xdg.configFile = {
        "dump/config.json".text = builtins.toJSON { server = "http://10.0.0.2:8081"; };
      };

      services.syncthing.enable = true;
      defaultConfigs.syncthing.enable = true;
      defaultConfigs.syncthing.knownFolders.scratch.enable = true;
      defaultConfigs.syncthing.knownFolders.ebooks.enable = true;

    };

}
