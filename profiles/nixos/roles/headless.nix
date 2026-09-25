{
  config,
  lib,
  ...
}:
# A machine that runs without a display, and that I never sit at: nexus,
# citadel, pylon. Import it next to ../base.nix.
#
# Everything here answers one question: "is this box remote?". Hardware,
# hosted services and network topology stay in the machine.
{
  # Closures get built on a workstation and pushed here, so they carry no
  # cache signature.
  nix.settings.require-sigs = false;

  # Nobody logs in to start user services, so the user manager must stay up.
  users.users.surma.linger = lib.mkDefault true;

  # Remote administration: my own key, plus the unattended deploy key.
  users.users.root.openssh.authorizedKeys.keys = [
    config.secrets.keys.surma
    (builtins.readFile ../../../assets/ssh-keys/id_deploy.pub)
  ];
}
