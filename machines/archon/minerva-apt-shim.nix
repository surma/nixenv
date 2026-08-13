# Builds the `apt-get` / `apt` verifying shim used to get Shopify's Minerva
# TPM/NSS dependency worker past its package-manager gate on NixOS.
#
# The interesting documentation lives at the top of ./minerva-apt-shim.sh —
# read that first. In short: this program verifies, it does not install, and
# it never reports success for something untrue.
#
# Deliberately built with `runtimeInputs = [ ]`: the shim must observe exactly
# the PATH its caller has, otherwise its assertions would not correspond to
# what the calling script will see. The two helpers it genuinely needs
# (`find`, `logger`) are therefore baked in by absolute store path.
{
  lib,
  writeShellApplication,
  findutils,
  util-linux,
  runCommand,
}:
let
  script =
    builtins.replaceStrings
      [ "@find@" "@logger@" ]
      [ "${findutils}/bin/find" "${util-linux}/bin/logger" ]
      (builtins.readFile ./minerva-apt-shim.sh);

  aptGet = writeShellApplication {
    name = "apt-get";
    runtimeInputs = [ ]; # intentionally empty — see header comment
    text = script;
    meta = {
      description = "Verifying (non-installing) apt-get stand-in for Fleet/Minerva scripts on NixOS";
      mainProgram = "apt-get";
    };
  };
in
# `apt` is the same program under a second name; the shim reports the name it
# was invoked as in its audit log.
runCommand "minerva-apt-shim"
  {
    inherit (aptGet.meta) description;
    passthru = { inherit aptGet; };
  }
  ''
    mkdir -p "$out/bin"
    ln -s ${lib.getExe aptGet} "$out/bin/apt-get"
    ln -s ${lib.getExe aptGet} "$out/bin/apt"
  ''
