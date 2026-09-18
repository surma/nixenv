{
  config,
  lib,
  ...
}:
# Keeps my user services running after logout on hosts whose system config I do
# not own. NixOS machines set users.users.surma.linger instead, see
# profiles/nixos/headless.nix.
{
  # Best-effort linger enablement for user services to survive logout.
  home.activation.enableLinger = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if command -v loginctl >/dev/null 2>&1; then
      if [ "$(loginctl show-user ${config.home.username} --property=Linger --value 2>/dev/null || true)" != "yes" ]; then
        loginctl enable-linger ${config.home.username} >/dev/null 2>&1 || true
      fi
    fi
  '';
}
