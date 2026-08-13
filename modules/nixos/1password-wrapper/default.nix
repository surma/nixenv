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
    { config, lib, ... }:
    let
      forwardedAgentMatch =
        ''Match host *,!gitea.surma.technology,!gitea-brain exec "test -n \"$SSH_CONNECTION\" && test -S \"$SSH_AUTH_SOCK\""'';
    in
    {
      programs.ssh.settings."${forwardedAgentMatch}" =
        lib.hm.dag.entryBefore [ "*" ] {
          IdentityAgent = "SSH_AUTH_SOCK";
        };

      programs.ssh.settings."*".IdentityAgent = ''"${config.home.homeDirectory}/.1password/agent.sock"'';

      # Autostart 1Password (patched) on Hyprland login. --silent keeps it
      # in the tray instead of popping a window on every login.
      wayland.windowManager.hyprland.extraConfig = ''
        hl.on("hyprland.start", function()
          hl.exec_cmd("${onepasswordCommand} --silent")
        end)
      '';
    };
}
