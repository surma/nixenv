{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ../../profiles/darwin/base.nix

    # Program modules are auto-loaded from ../../modules/programs
  ];

  system.stateVersion = 5;
  networking.hostName = "dragoon";

  homebrew = {
    casks = [
      "nvidia-geforce-now"
      "magicavoxel"
    ];
  };

  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 3;
      Minute = 0;
    };
    options = "--delete-older-than 14d";
  };

  ids.gids.nixbld = 30000;

  programs.signal.enable = true;
  programs.obs.enable = true;

  home-manager.users.${config.system.primaryUser} = import ./home.nix;

}
