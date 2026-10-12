{
  config,
  pkgs,
  lib,
  osConfig,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
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
    ../../profiles/home-manager/gui/wayland.nix
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
        pkgs-unstable.ollama-vulkan
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

    defaultConfigs.eww.scriptButtons.connect-surmbeats =
      let
        bluetoothctl = lib.getExe' osConfig.hardware.bluetooth.package "bluetoothctl";
      in
      {
        label = "";
        text = "Connect SurmBeats";
        command = toString (
          pkgs.writers.writeNu "connect-surmbeats" ''
            ${bluetoothctl} devices Paired | from ssv -m 1 -n | where column2 =~ SurmBeats | first | ${bluetoothctl} connect $in.column1
          ''
        );
      };

    programs.handy.enable = true;
    defaultConfigs.handy.enable = true;

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    # Keep herdr sessions alive across restarts of the graphical session.
    programs.herdr.server.enable = true;

    # No Install section, so the unit never starts by itself. Start it with
    # `systemctl --user start ollama` when needed.
    systemd.user.services.ollama = {
      Unit.Description = "Ollama server";
      Service = {
        Environment = [
          "OLLAMA_VULKAN=1"
          "OLLAMA_IGPU_ENABLE=1"
          "OLLAMA_CONTEXT_LENGTH=131072"
          "OLLAMA_FLASH_ATTENTION=1"
          "OLLAMA_KV_CACHE_TYPE=q8_0"
        ];
        ExecStart = "${pkgs-unstable.ollama-vulkan}/bin/ollama serve";
      };
    };
  };
}
