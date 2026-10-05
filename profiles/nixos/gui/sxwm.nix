{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# SXWM-specific system settings for profiles/nixos/gui/wayland.nix.
{
  imports = [ inputs.sxwm.nixosModules.default ];

  config = lib.mkIf (config.gui.compositor == "sxwm") {
    programs.sxwm.enable = true;
    # See the same setting in ./niri.nix.
    services.displayManager.defaultSession = "sxwm";
    # SXWM starts xwayland-satellite from PATH when the first X11 client
    # connects.
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
