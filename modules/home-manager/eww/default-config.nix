{
  config,
  lib,
  pkgs,
  ...
}:
let
  niriEnabled = config.defaultConfigs.niri.enable;

  hyprlandWorkspaces = pkgs.writeShellApplication {
    name = "eww-hyprland-workspaces";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.socat
    ];
    text = builtins.readFile ./hyprland-workspaces.sh;
  };
  niriWorkspaces = pkgs.writeShellApplication {
    name = "eww-niri-workspaces";
    runtimeInputs = [
      pkgs.jq
      pkgs.niri
    ];
    text = builtins.readFile ./niri-workspaces.sh;
  };
  workspaceScript = if niriEnabled then niriWorkspaces else hyprlandWorkspaces;

  focusWorkspace = pkgs.writeShellApplication {
    name = "eww-focus-workspace";
    runtimeInputs = if niriEnabled then [ pkgs.niri ] else [ pkgs.hyprland ];
    text =
      if niriEnabled then
        ''
          niri msg action focus-monitor "$1"
          niri msg action focus-workspace "$2"
        ''
      else
        ''
          hyprctl dispatch "hl.dsp.focus({ workspace = $2 })"
        '';
  };

  outputListCommand =
    if niriEnabled then
      "niri msg --json outputs | jq -r 'to_entries[] | select(.value.logical != null) | .key'"
    else
      "hyprctl -j monitors | jq -r '.[] | select(.disabled != true) | .name'";
  openBars = pkgs.writeShellApplication {
    name = "eww-open-bars";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.eww
      pkgs.jq
    ]
    ++ (if niriEnabled then [ pkgs.niri ] else [ pkgs.hyprland ]);
    text = ''
      # eww.service is Type=simple, so wait up to 5 s for the daemon socket.
      for attempt in {1..25}; do
        if eww ping >/dev/null 2>/dev/null; then
          break
        fi
        if [[ "$attempt" -eq 25 ]]; then
          exit 1
        fi
        sleep 0.2
      done
      ${outputListCommand} | while IFS= read -r output; do
        eww open --id "bar-$output" --arg "screen=$output" bar
      done
    '';
  };

  volume = pkgs.writeShellApplication {
    name = "eww-volume";
    runtimeInputs = [
      pkgs.gawk
      pkgs.wireplumber
    ];
    text = ''
      read -r _ level state < <(wpctl get-volume @DEFAULT_AUDIO_SINK@)
      percentage="$(awk -v level="$level" 'BEGIN { printf "%d", level * 100 }')"
      if [[ "$state" == "[MUTED]" ]]; then
        printf ' %s%%\n' "$percentage"
      else
        printf ' %s%%\n' "$percentage"
      fi
    '';
  };
  battery = pkgs.writeShellApplication {
    name = "eww-battery";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for battery in /sys/class/power_supply/BAT*; do
        if [[ -r "$battery/capacity" ]]; then
          printf ' %s%%\n' "$(cat "$battery/capacity")"
          exit 0
        fi
      done
    '';
  };

  stayAwakePath = lib.makeBinPath [
    config.customScripts."stay-awake".package
    pkgs.eww
    pkgs.systemd
  ];

  sunsetEnabled = lib.attrByPath [ "customScripts" "toggle-sunset" "enable" ] false config;
  sunsetScript =
    if sunsetEnabled then
      lib.attrByPath [ "customScripts" "toggle-sunset" "package" ] null config
    else
      null;
  sunsetPath = lib.makeBinPath (
    lib.optionals (sunsetScript != null) [
      sunsetScript
      pkgs.hyprland
      pkgs.systemd
    ]
  );
  sunsetWidget =
    if sunsetScript == null then
      ""
    else
      ''(button :class "sunset" :onclick "PATH=${sunsetPath} toggle-sunset" (label :text "🟧"))'';

  yuckConfig =
    builtins.replaceStrings
      [
        "@WORKSPACES@"
        "@VOLUME@"
        "@BATTERY@"
        "@STAY_AWAKE_PATH@"
        "@FOCUS_WORKSPACE@"
        "@PAVUCONTROL@"
        "@SUNSET_WIDGET@"
      ]
      [
        (lib.getExe workspaceScript)
        (lib.getExe volume)
        (lib.getExe battery)
        stayAwakePath
        (lib.getExe focusWorkspace)
        (lib.getExe pkgs.pavucontrol)
        sunsetWidget
      ]
      (builtins.readFile ./eww.yuck);
in
{
  options.defaultConfigs.eww.enable = lib.mkEnableOption "the Eww bar configuration";

  config = lib.mkIf config.defaultConfigs.eww.enable {
    home.packages = [ pkgs.pavucontrol ];

    programs.eww = {
      inherit yuckConfig;
      scssConfig = builtins.readFile ./eww.scss;
    };

    systemd.user.services.eww-bar = {
      Unit = {
        Description = "Open the Eww bar on each output";
        # Without the explicit order after the target, systemd orders the
        # target after this unit, which makes a cycle through eww.service.
        After = [
          "eww.service"
          config.wayland.systemd.target
        ];
        Requires = [ "eww.service" ];
        PartOf = [ config.wayland.systemd.target ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe openBars;
        RemainAfterExit = true;
      };
      Install.WantedBy = [ config.wayland.systemd.target ];
    };
  };
}
