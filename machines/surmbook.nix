{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../darwin/base.nix

    ../common/signal
    ../common/obs
    ../common/obsidian
  ];

  system.stateVersion = 5;

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
        ../common/spotify
        ../common/telegram

        ../home-manager/opencode
        ../home-manager/claude-code
        ../home-manager/syncthing

        ../home-manager/unfree-apps.nix

        ../home-manager/base.nix
        ../home-manager/graphical.nix
        ../home-manager/keyboard-dev.nix
        ../home-manager/workstation.nix
        ../home-manager/physical.nix
        ../home-manager/macos.nix
        ../home-manager/experiments.nix
        ../home-manager/cloud.nix
        ../home-manager/nixdev.nix
        ../home-manager/javascript.nix
        ../home-manager/dev.nix
        ../home-manager/godot.nix
      ];

      home.stateVersion = "24.05";

      home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmbook";

      allowedUnfreeApps = [
        "spotify"
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
          tmpmemstore
          amber
          badage
        ]
      );

      programs.spotify.enable = true;
      programs.telegram.enable = true;
      programs.claude-code.enable = true;
      defaultConfigs.claude-code.enable = true;

      customScripts.denix.enable = true;
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
