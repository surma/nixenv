{
  config,
  lib,
  pkgs,
  ...
}:
# Hyprland-specific system settings for profiles/nixos/gui/wayland.nix.
let
  hyprlandPackage = pkgs.hyprland;
  hyprlandPortalPackage = pkgs.xdg-desktop-portal-hyprland;
in
{
  config = lib.mkIf (config.gui.compositor == "hyprland") {
    programs.hyprland.enable = true;
    programs.hyprland.package = hyprlandPackage;
    programs.hyprland.portalPackage = hyprlandPortalPackage;
    # See the same setting in ./niri.nix.
    services.displayManager.defaultSession = "hyprland";

    xdg.portal.extraPortals = [ hyprlandPortalPackage ];

    environment.systemPackages = [ pkgs.hyprsunset ];
  };
}
