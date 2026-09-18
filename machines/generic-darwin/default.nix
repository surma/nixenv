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
      ../../profiles/home-manager/roles/dev.nix
      ../../profiles/home-manager/platform/macos.nix
    ];

    home.stateVersion = "25.11";
  };
}
