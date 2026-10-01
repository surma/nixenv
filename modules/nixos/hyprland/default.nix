{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
let
  hyprlandPackage = pkgs.hyprland;
  hyprlandPortalPackage = pkgs.xdg-desktop-portal-hyprland;

  # The NixOS module applies `.override { systemdSupport = true; }`. The Waybar flake
  # package does not accept that argument. systemdSupport is already on by default on Linux.
  waybarPackage = inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.waybar;
  waybarPackageForNixos = waybarPackage // {
    override = _: waybarPackage;
  };
in
{
  environment.systemPackages = with pkgs; [
    brightnessctl
    playerctl
    wireplumber
  ];

  programs.hyprland.enable = true;
  programs.hyprland.package = hyprlandPackage;
  programs.hyprland.portalPackage = hyprlandPortalPackage;

  xdg.portal = {
    enable = true;
    extraPortals = [ hyprlandPortalPackage ];
  };

  programs.waybar.enable = true;
  programs.waybar.package = waybarPackageForNixos;
  services.displayManager.gdm.enable = true;
}
