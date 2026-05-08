{ ... }:
{
  imports = [
    ../nix-on-droid/base.nix
  ];

  system.stateVersion = "24.05";

  home-manager.config =
    { config, ... }:
    {
      imports = [
        ../../profiles/home-manager/base.nix
      ];

      home.stateVersion = "24.05";
    };
}
