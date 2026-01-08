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
        ../home-manager/base.nix
      ];

      home.stateVersion = "24.05";

      home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#generic-android";
    };
}
