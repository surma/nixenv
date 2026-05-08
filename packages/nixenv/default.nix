{
  callPackage,
  writeShellApplication,
  ...
}:
let
  nixenvupdate = callPackage ../../scripts/nixenvupdate { };
in
writeShellApplication {
  name = "nixenv";
  runtimeInputs = [ nixenvupdate ];
  text = ''
    exec nixenvupdate "$@"
  '';
}
