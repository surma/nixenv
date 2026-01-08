{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) makeDesktopItem;
in
{
  environment.systemPackages = [
    (makeDesktopItem {
      name = "1password-wrapper";
      desktopName = "1Password (patched)";
      exec = "${config.programs._1password-gui.package}/bin/1password --ozone-platform=x11";
    })
  ];

  home-manager.users.surma =
    { config, ... }:
    {
      programs.ssh.matchBlocks."*".extraOptions = {
        "IdentityAgent" = ''"${config.home.homeDirectory}/.1password/agent.sock"'';
      };
    };
}
