{
  lib,
  pkgs,
  nixenv ? null,
  ...
}:
let
  nixenvupdate = pkgs.callPackage ../../../scripts/nixenvupdate { };
in
{
  # Set by profiles/home-manager/gui/gui-apps.nix, so other profiles can
  # install graphical tools only on machines with a desktop.
  options.nixenv.gui = lib.mkEnableOption "the graphical desktop profile";

  config = lib.mkIf (nixenv != null) {
    home.packages = [ nixenvupdate ];

    home.sessionVariables = {
      NIXENV_FLAKE_REF = lib.mkDefault nixenv.flakeRef;
      NIXENV_MACHINE_NAME = lib.mkDefault nixenv.machineName;
      NIXENV_CONFIG_KIND = lib.mkDefault nixenv.configKind;
    };
  };
}
