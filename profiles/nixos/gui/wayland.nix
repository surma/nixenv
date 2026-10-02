{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# The system half of a Wayland session: the greeter and compositor-neutral
# helpers. Import it next to ./desktop.nix.
#
# The user half is profiles/home-manager/gui/wayland.nix.
let
  # The NixOS module applies `.override { systemdSupport = true; }`. The Waybar flake
  # package does not accept that argument. systemdSupport is already on by default on Linux.
  waybarPackage = inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.waybar;
  waybarPackageForNixos = waybarPackage // {
    override = _: waybarPackage;
  };
in
{
  imports = [ ./hyprland.nix ];

  options.gui.compositor = lib.mkOption {
    type = lib.types.enum [
      "hyprland"
      "niri"
    ];
    default = "hyprland";
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

    programs.waybar.enable = true;
    programs.waybar.package = waybarPackageForNixos;
    services.displayManager.gdm.enable = true;
  };
}
