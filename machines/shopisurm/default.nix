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

    # Program modules are auto-loaded from ../../modules/programs

    ../../scripts
  ];

  system.stateVersion = 5;

  nix.extraOptions = ''
    !include nix.conf.d/shopify.conf
  '';

  programs.obs.enable = true;

  home-manager.users.${config.system.primaryUser} = import ./home.nix;
}
