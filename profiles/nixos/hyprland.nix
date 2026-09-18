{
  pkgs,
  ...
}:
# The system half of a Hyprland session: the compositor, the portal, the
# greeter, and the session helpers. Import it next to ./desktop.nix.
#
# The user half is profiles/home-manager/hyprland.nix.
{
  imports = [
    ../../modules/nixos/hyprland
  ];

  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    hyprlock
    hyprsunset
  ];

  # hyprlock talks to fprintd itself, so its PAM stack must not prompt for a
  # fingerprint a second time.
  security.pam.services.hyprlock = {
    fprintAuth = false;
  };
}
