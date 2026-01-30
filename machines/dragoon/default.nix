{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../../profiles/darwin/base.nix

    # Programs now globally injected
    # ../../modules/programs/signal
    # ../../modules/programs/obs
    # ../../modules/programs/obsidian
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

  home-manager.users.${config.system.primaryUser} = import ./home.nix;

}
