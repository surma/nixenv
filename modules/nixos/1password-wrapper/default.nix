{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) makeDesktopItem;
  onepasswordCommand = "${config.programs._1password-gui.package}/bin/1password --ozone-platform=x11";
in
{
  environment.systemPackages = [
    (makeDesktopItem {
      name = "1password-wrapper";
      desktopName = "1Password (patched)";
      exec = onepasswordCommand;
    })
  ];

  home-manager.users.surma =
    { config, ... }:
    {
      programs.ssh.matchBlocks."*".extraOptions = {
        "IdentityAgent" = ''"${config.home.homeDirectory}/.1password/agent.sock"'';
      };

      # Autostart 1Password (patched) on Hyprland login. --silent keeps it
      # in the tray instead of popping a window on every login.
      wayland.windowManager.hyprland.extraConfig = ''
        exec-once = ${onepasswordCommand} --silent
      '';
    };
}
