{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/roles/dev.nix
    ../../profiles/home-manager/roles/nixdev.nix
    ../../profiles/home-manager/platform/linux.nix
    ../../profiles/home-manager/gui/fonts.nix
    ../../profiles/home-manager/gui/terminal.nix
    ../../profiles/home-manager/gui/gui-apps.nix
    ../../profiles/home-manager/platform/physical.nix
    ../../profiles/home-manager/gui/hyprland.nix
    ../../profiles/home-manager/roles/workstation.nix
    ../../profiles/home-manager/roles/ai.nix
  ];

  config = {
    agent.skills = [
      ../../assets/skills/orchestrator
      ../../assets/skills/subagent
    ];

    allowedUnfreeApps = [
      "slack"
      "discord"
    ];

    home.packages = (
      with pkgs;
      [
        slack
        nodejs_24
        chromium
        kdePackages.dolphin
        vlc
        qview
        picocom
      ]
    );

    home.stateVersion = "26.05";

    programs.discord.enable = true;
    # programs.discord.platform = "wayland";
    programs.telegram.enable = true;

    # TODO(surma): Tune for dark-archon's actual display once known. This is
    # archon's 13 inch 2256x1504 panel.
    programs.wezterm.fontSize = 10;

    secrets.items.m-config.target = "${config.home.homeDirectory}/.config/m/config.yaml";

    # programs.opencode.enable = true;
    # defaultConfigs.opencode.enable = true;
    programs.handy.enable = true;
    defaultConfigs.handy.enable = true;

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    # Sunshine must follow the actual Hyprland session, not the generic
    # graphical-session.target that GDM also exposes to its greeter user.
    # The NixOS Sunshine unit remains the single service definition; this
    # target dependency supplies the Hyprland-only autostart edge.
    systemd.user.targets."hyprland-session".Unit.Wants = [
      "sunshine.service"
    ];
  };
}
