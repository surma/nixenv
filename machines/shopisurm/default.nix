{
  options,
  config,
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage;
in
{
  imports = [
    ../../profiles/darwin/base.nix
    ./nix-custom-conf-workaround.nix

    # Program modules are auto-loaded from ../../modules/programs

    ../../scripts
  ];

  system.stateVersion = 5;

  programs.obs.enable = true;

  home-manager.users.${config.system.primaryUser} = import ./home.nix;
}
