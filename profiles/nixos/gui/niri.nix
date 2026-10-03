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
    # GDM starts the last session that AccountsService saved, even when that
    # session no longer exists. A default session makes GDM overwrite it.
    services.displayManager.defaultSession = "niri";
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
