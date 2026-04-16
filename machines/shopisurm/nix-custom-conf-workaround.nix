{ lib, config, ... }:
{
  # Temporary workaround: bypass nix-darwin's extra activation-time checks on
  # this machine so TEC janitor's /etc/nix/nix.custom.conf does not abort
  # activation.
  #
  # Note: this also skips other fragments appended to
  # system.activationScripts.checks.text (for example some /etc collision
  # checks), so this should stay machine-local and temporary.
  system.activationScripts.checks.text = lib.mkForce ''
    ${config.system.checks.text}

    if [[ "''${checkActivation:-0}" -eq 1 ]]; then
      echo "ok" >&2
      exit 0
    fi
  '';
}
