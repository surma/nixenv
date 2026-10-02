{
  config,
  lib,
  pkgs,
  ...
}:
# Niri-specific system settings for profiles/nixos/gui/wayland.nix.
{
  config = lib.mkIf (config.gui.compositor == "niri") {
    programs.niri.enable = true;
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
