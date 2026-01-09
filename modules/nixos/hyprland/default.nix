{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
let
  # For bleeding edge
  # hyprlandPackage = inputs.hyprland.packages.${system}.default;
  # hyprlandPortalPackage = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;

  hyprlandPackage = pkgs.hyprland;
  hyprlandPortalPackage = pkgs.xdg-desktop-portal-hyprland;
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
  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
}
