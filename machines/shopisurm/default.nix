{
  options,
  config,
  pkgs,
  lib,
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

  security.pam.services.sudo_local.text = lib.mkForce ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
    auth       sufficient     pam_tid.so
  '';

  programs.obs.enable = true;

  home-manager.users.${config.system.primaryUser} = import ./home.nix;
}
