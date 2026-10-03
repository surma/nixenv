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

  setsidPath = lib.getExe' pkgs.util-linux "setsid";

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
      pkgs.systemd
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
      for _ in {1..25}; do
        if busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>/dev/null; then
          exit 0
        fi
        sleep 0.2
      done
      exit 1
    '';
  };

  volume = pkgs.writeShellApplication {
    name = "eww-volume";
    runtimeInputs = [
      pkgs.gawk
      pkgs.wireplumber
    ];
    text = ''
      read_volume() {
        local output level state percentage
        output="$(wpctl get-volume "$1" 2>/dev/null)" || return 1
        read -r _ level state <<< "$output"
        percentage="$(awk -v level="$level" 'BEGIN { printf "%d", level * 100 }')"
        printf '%s %s\n' "$percentage" "$state"
      }

      if [[ "''${1:-}" == "--state" ]]; then
        if output="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"; then
          if [[ "$output" == *"[MUTED]"* ]]; then
            printf 'muted\n'
          else
            printf 'normal\n'
          fi
        else
          printf 'normal\n'
        fi
        exit 0
      fi

      if ! sink="$(read_volume @DEFAULT_AUDIO_SINK@)"; then
        exit 0
      fi
      read -r sink_percentage sink_state <<< "$sink"

      if [[ "$sink_state" == "[MUTED]" ]]; then
        sink_format=""
      else
        if (( sink_percentage < 34 )); then
          volume_icon=""
        elif (( sink_percentage < 67 )); then
          volume_icon=""
        else
          volume_icon=""
        fi
        sink_format="$sink_percentage% $volume_icon"
      fi

      if source="$(read_volume @DEFAULT_AUDIO_SOURCE@)"; then
        read -r source_percentage source_state <<< "$source"
        if [[ "$source_state" == "[MUTED]" ]]; then
          source_format=""
        else
          source_format="$source_percentage% "
        fi
        printf '%s %s\n' "$sink_format" "$source_format"
      else
        printf '%s\n' "$sink_format"
      fi
    '';
  };
  battery = pkgs.writeShellApplication {
    name = "eww-battery";
    text = ''
      battery=""
      for candidate in /sys/class/power_supply/BAT*; do
        if [[ -r "$candidate/capacity" ]]; then
          battery="$candidate"
          break
        fi
      done
      [[ -n "$battery" ]] || exit 0

      capacity="$(<"$battery/capacity")"
      status="$(<"$battery/status")"
      plugged=false
      for supply in /sys/class/power_supply/*; do
        if [[ -r "$supply/online" ]] && [[ "$(<"$supply/online")" == "1" ]]; then
          plugged=true
          break
        fi
      done

      icon_index=$(( capacity / 20 ))
      if (( icon_index > 4 )); then
        icon_index=4
      fi
      icons=("" "" "" "" "")
      icon="''${icons[$icon_index]}"

      if [[ "$status" == "Charging" ]]; then
        format="$capacity% "
      elif [[ "$plugged" == true ]]; then
        format="$capacity% "
      else
        format="$capacity% $icon"
      fi

      if [[ "''${1:-}" == "--class" ]]; then
        class="battery"
        if [[ "$status" == "Charging" ]]; then
          class="$class charging"
        fi
        if [[ "$plugged" == true ]]; then
          class="$class plugged"
        fi
        if (( capacity <= 15 )); then
          class="$class critical"
        elif (( capacity <= 30 )); then
          class="$class warning"
        fi
        printf '%s\n' "$class"
      else
        printf '%s\n' "$format"
      fi
    '';
  };
  powerProfile = pkgs.writeShellApplication {
    name = "eww-power-profile";
    runtimeInputs = [
      pkgs.gawk
      pkgs.power-profiles-daemon
    ];
    text = ''
      profile="$(powerprofilesctl get 2>/dev/null)" || exit 0
      if [[ "''${1:-}" != "--tooltip" ]]; then
        printf '%s\n' "$profile"
        exit 0
      fi

      profile_list="$(powerprofilesctl list 2>/dev/null)" || exit 0
      driver="$(
        awk -v profile="$profile" '
          /^[[:space:]]*\*?[[:space:]]*(performance|balanced|power-saver):[[:space:]]*$/ {
            current = $0
            sub(/^[[:space:]]*\*?[[:space:]]*/, "", current)
            sub(/:[[:space:]]*$/, "", current)
            in_profile = current == profile
            next
          }
          in_profile && /^[[:space:]]*Driver:[[:space:]]*/ {
            sub(/^[[:space:]]*Driver:[[:space:]]*/, "")
            print
            exit
          }
        ' <<< "$profile_list"
      )"
      printf 'Power profile: %s\nDriver: %s\n' "$profile" "$driver"
    '';
  };
  cyclePowerProfile = pkgs.writeShellApplication {
    name = "eww-cycle-power-profile";
    runtimeInputs = [
      pkgs.gawk
      pkgs.power-profiles-daemon
    ];
    text = ''
      profile_list="$(powerprofilesctl list 2>/dev/null)" || exit 0
      current="$(powerprofilesctl get 2>/dev/null)" || exit 0
      mapfile -t profiles < <(
        awk '
          /^[[:space:]]*\*?[[:space:]]*(performance|balanced|power-saver):[[:space:]]*$/ {
            profile = $0
            sub(/^[[:space:]]*\*?[[:space:]]*/, "", profile)
            sub(/:[[:space:]]*$/, "", profile)
            print profile
          }
        ' <<< "$profile_list"
      )
      for index in "''${!profiles[@]}"; do
        if [[ "''${profiles[$index]}" == "$current" ]]; then
          next_index=$(( (index + 1) % ''${#profiles[@]} ))
          exec powerprofilesctl set "''${profiles[$next_index]}"
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
      ''(button :class "sunset" :onclick "PATH=${sunsetPath} ${setsidPath} -f toggle-sunset" (label :text "🟧"))'';

  yuckConfig =
    builtins.replaceStrings
      [
        "@WORKSPACES@"
        "@VOLUME@"
        "@VOLUME_STATE@"
        "@BATTERY@"
        "@BATTERY_CLASS@"
        "@STAY_AWAKE_PATH@"
        "@STAY_AWAKE_CLICK@"
        "@FOCUS_WORKSPACE@"
        "@PAVUCONTROL@"
        "@POWER_PROFILE@"
        "@POWER_PROFILE_TOOLTIP@"
        "@POWER_PROFILE_CYCLE@"
        "@SUNSET_WIDGET@"
      ]
      [
        (lib.getExe workspaceScript)
        (lib.getExe volume)
        "${lib.getExe volume} --state"
        (lib.getExe battery)
        "${lib.getExe battery} --class"
        stayAwakePath
        "PATH=${stayAwakePath} ${setsidPath} -f stay-awake toggle"
        "${setsidPath} -f ${lib.getExe focusWorkspace}"
        "${setsidPath} -f ${lib.getExe pkgs.pavucontrol}"
        (lib.getExe powerProfile)
        "${lib.getExe powerProfile} --tooltip"
        "${setsidPath} -f ${lib.getExe cyclePowerProfile}"
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
