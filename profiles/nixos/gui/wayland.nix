{
  config,
  lib,
  pkgs,
  ...
}:
# The system half of a Wayland session: the greeter and compositor-neutral
# helpers. Import it next to ./desktop.nix.
#
# The user half is profiles/home-manager/gui/wayland.nix.
{
  imports = [
    ./hyprland.nix
    ./niri.nix
    ./sxwm.nix
  ];

  options.gui.compositor = lib.mkOption {
    type = lib.types.enum [
      "hyprland"
      "niri"
      "sxwm"
    ];
    default = "niri";
    description = "The Wayland compositor to use.";
  };

  config = {
    environment.systemPackages = with pkgs; [
      brightnessctl
      playerctl
      wireplumber
      hyprpolkitagent
      hyprlock
    ];

    # hyprlock talks to fprintd itself, so its PAM stack must not prompt for a
    # fingerprint a second time.
    security.pam.services.hyprlock = {
      fprintAuth = false;
    };

    xdg.portal.enable = true;

    services.displayManager.gdm.enable = true;
  };
}
