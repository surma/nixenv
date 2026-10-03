{
  config,
  pkgs,
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
      programs.ssh.settings."*".IdentityAgent = ''"${config.home.homeDirectory}/.1password/agent.sock"'';

      # 1Password creates its tray icon only once, at start. Start it after
      # the bar, so that the tray exists. --silent keeps it in the tray
      # instead of popping a window on every login.
      systemd.user.services."1password" = {
        Unit = {
          Description = "1Password";
          After = [
            "eww-bar.service"
            config.wayland.systemd.target
          ];
          PartOf = [ config.wayland.systemd.target ];
        };
        Service.ExecStart = "${onepasswordCommand} --silent";
        Install.WantedBy = [ config.wayland.systemd.target ];
      };
    };
}
