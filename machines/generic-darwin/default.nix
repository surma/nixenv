{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../profiles/darwin/base.nix
  ];

  system.stateVersion = 5;

  home-manager.users.${config.system.primaryUser} = {
    imports = [
      ../../profiles/home-manager/core.nix
      ../../profiles/home-manager/extras.nix
      ../../profiles/home-manager/dev.nix
      ../../profiles/home-manager/macos.nix
    ];

    home.stateVersion = "25.11";
  };
}
