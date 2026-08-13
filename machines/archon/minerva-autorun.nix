# Builds the wrapper that runs the Minerva TPM/NSS dependency worker.
#
# See the header of ./minerva-autorun.sh for what it does and why.
#
# As with the apt-get shim, `runtimeInputs = [ ]` is deliberate: the wrapper
# execs the worker, so anything it added to PATH would also be visible to the
# worker (and therefore to the apt-get shim's checks). Keeping PATH untouched
# means the worker runs under exactly the PATH systemd gives this unit, which
# minerva.nix makes byte-identical to orbit's.
{
  writeShellApplication,
  coreutils,
  bash,
  util-linux,
}:
writeShellApplication {
  name = "minerva-autorun";
  runtimeInputs = [ ]; # intentionally empty — see header comment
  text =
    builtins.replaceStrings
      [ "@coreutils@" "@bash@" "@flock@" ]
      [ "${coreutils}/bin" "${bash}/bin/bash" "${util-linux}/bin/flock" ]
      (builtins.readFile ./minerva-autorun.sh);
  meta = {
    description = "Runs the Fleet-dropped Minerva TPM/NSS dependency worker once, idempotently";
    mainProgram = "minerva-autorun";
  };
}
