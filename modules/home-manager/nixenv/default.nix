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
  config = lib.mkIf (nixenv != null) {
    home.packages = [ nixenvupdate ];

    home.sessionVariables = {
      NIXENV_FLAKE_REF = lib.mkDefault nixenv.flakeRef;
      NIXENV_MACHINE_NAME = lib.mkDefault nixenv.machineName;
      NIXENV_CONFIG_KIND = lib.mkDefault nixenv.configKind;
    };
  };
}
