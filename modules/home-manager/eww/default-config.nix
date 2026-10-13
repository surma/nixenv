{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  sxPalette = import ../../../lib/sx-palette.nix { inherit inputs; };
  niriEnabled = config.defaultConfigs.niri.enable;
  sxwmEnabled = config.defaultConfigs.sxwm.enable;
  sxwm = inputs.sx.packages.${pkgs.stdenv.hostPlatform.system}.sxwm;

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
  sxwmWorkspaces = pkgs.writeShellApplication {
    name = "eww-sxwm-workspaces";
    runtimeInputs = [
      pkgs.jq
      sxwm
    ];
    text = builtins.readFile ./sxwm-workspaces.sh;
  };
  workspaceScript =
    if sxwmEnabled then
      sxwmWorkspaces
    else if niriEnabled then
      niriWorkspaces
    else
      hyprlandWorkspaces;

  focusWorkspace = pkgs.writeShellApplication {
    name = "eww-focus-workspace";
    runtimeInputs =
      if sxwmEnabled then
        [
          pkgs.jq
          sxwm
        ]
      else if niriEnabled then
        [ pkgs.niri ]
      else
        [ pkgs.hyprland ];
    text =
      # config.js registers switch-to-tag with the same behavior as meh+letter.
      if sxwmEnabled then
        ''
          sxwmctl commands.run "$(jq -cn --arg tag "$2" '{name: "switch-to-tag", args: {tag: $tag}}')"
        ''
      else if niriEnabled then
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
    if sxwmEnabled then
      "sxwmctl state.get | jq -r '.screens[].id'"
    else if niriEnabled then
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
    ++ (
      if sxwmEnabled then
        [ sxwm ]
      else if niriEnabled then
        [ pkgs.niri ]
      else
        [ pkgs.hyprland ]
    );
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
      eww update stay_awake="$(PATH=${stayAwakePath} stay-awake status)"
      ${lib.optionalString (sunsetScript != null) ''
        eww update sunset_state="$(PATH=${sunsetPath} toggle-sunset status)"
      ''}
      ${lib.optionalString (scriptButtons != { }) ''
        eww update scripts_running="$(${lib.getExe scriptsRunning})"
      ''}
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
      pkgs.coreutils
      pkgs.gawk
      pkgs.pulseaudio
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

      render() {
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
          return
        fi

        if ! sink="$(read_volume @DEFAULT_AUDIO_SINK@)"; then
          return
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
      }

      while true; do
        {
          render "$@"
          while IFS= read -r event; do
            if [[ "$event" == *" on sink #"* || "$event" == *" on source #"* || "$event" == *" on server #"* ]]; then
              render "$@"
            fi
          done
        } < <(pactl subscribe 2>/dev/null || true)
        sleep 0.2
      done
    '';
  };
  battery = pkgs.writeShellApplication {
    name = "eww-battery";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dbus
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      render() {
        local device=/org/freedesktop/UPower/devices/DisplayDevice
        local interface=org.freedesktop.UPower.Device
        local present percentage state on_battery capacity plugged

        if ! present="$(busctl --system --json=short get-property \
          org.freedesktop.UPower "$device" "$interface" IsPresent 2>/dev/null | jq -r '.data')"; then
          return
        fi
        if [[ "$present" != "true" ]]; then
          printf '\n'
          return
        fi
        if ! percentage="$(busctl --system --json=short get-property \
          org.freedesktop.UPower "$device" "$interface" Percentage 2>/dev/null | jq -r '.data')"; then
          return
        fi
        if ! state="$(busctl --system --json=short get-property \
          org.freedesktop.UPower "$device" "$interface" State 2>/dev/null | jq -r '.data')"; then
          return
        fi
        if ! on_battery="$(busctl --system --json=short get-property \
          org.freedesktop.UPower /org/freedesktop/UPower \
          org.freedesktop.UPower OnBattery 2>/dev/null | jq -r '.data')"; then
          return
        fi

        printf -v capacity '%.0f' "$percentage"
        plugged=false
        if [[ "$on_battery" == "false" ]]; then
          plugged=true
        fi

        icon_index=$(( capacity / 20 ))
        if (( icon_index > 4 )); then
          icon_index=4
        fi
        icons=("" "" "" "" "")
        icon="''${icons[$icon_index]}"

        if (( state == 1 )); then
          format="$capacity% "
        elif [[ "$plugged" == true ]]; then
          format="$capacity% "
        else
          format="$capacity% $icon"
        fi

        if [[ "''${1:-}" == "--class" ]]; then
          class="battery"
          if (( state == 1 )); then
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
      }

      while true; do
        {
          render "$@"
          while IFS= read -r event; do
            if [[ "$event" == *"member=PropertiesChanged"* ]]; then
              render "$@"
            fi
          done
        } < <(dbus-monitor --system \
          "type='signal',sender='org.freedesktop.UPower',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" \
          2>/dev/null || true)
        sleep 0.2
      done
    '';
  };
  powerProfile = pkgs.writeShellApplication {
    name = "eww-power-profile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dbus
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      render() {
        local active profiles driver
        if ! active="$(
          busctl --system --json=short get-property \
            net.hadess.PowerProfiles /net/hadess/PowerProfiles \
            net.hadess.PowerProfiles ActiveProfile | jq -r '.data'
        )"; then
          return
        fi
        if [[ "''${1:-}" != "--tooltip" ]]; then
          printf '%s\n' "$active"
          return
        fi

        if ! profiles="$(busctl --system --json=short get-property \
          net.hadess.PowerProfiles /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles Profiles)"; then
          return
        fi
        driver="$(jq -r --arg profile "$active" \
          '.data[] | select(.Profile.data == $profile) | .Driver.data' <<< "$profiles")"
        printf 'Power profile: %s (Driver: %s)\n' "$active" "$driver"
      }

      while true; do
        {
          render "$@"
          while IFS= read -r event; do
            if [[ "$event" == *"member=PropertiesChanged"* ]]; then
              render "$@"
            fi
          done
        } < <(dbus-monitor --system \
          "type='signal',sender='net.hadess.PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'" \
          2>/dev/null || true)
        sleep 0.2
      done
    '';
  };
  cyclePowerProfile = pkgs.writeShellApplication {
    name = "eww-cycle-power-profile";
    runtimeInputs = [
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      profiles="$(busctl --system --json=short get-property \
        net.hadess.PowerProfiles /net/hadess/PowerProfiles \
        net.hadess.PowerProfiles Profiles)"
      current="$(busctl --system --json=short get-property \
        net.hadess.PowerProfiles /net/hadess/PowerProfiles \
        net.hadess.PowerProfiles ActiveProfile | jq -r '.data')"
      next="$(jq -r --arg current "$current" '
        [.data[].Profile.data] as $profiles
        | ($profiles | index($current)) as $index
        | $profiles[($index + 1) % ($profiles | length)]
      ' <<< "$profiles")"
      busctl --system set-property net.hadess.PowerProfiles \
        /net/hadess/PowerProfiles net.hadess.PowerProfiles \
        ActiveProfile s "$next"
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
      pkgs.eww
      pkgs.systemd
    ]
  );
  sunsetDefinition =
    if sunsetScript == null then
      ""
    else
      ''(defvar sunset_state "deactivated")'';
  sunsetWidget =
    if sunsetScript == null then
      ""
    else
      ''(button :class {sunset_state == "activated" ? "sunset active" : "sunset"} :onclick "PATH=${sunsetPath} ${setsidPath} -f toggle-sunset" (label :text ""))'';

  # The script menu. A bar button opens a window with one row per script.
  # A click on a row starts the script in a transient systemd unit. The unit
  # allows only one run at a time and keeps the output in the journal.
  scriptButtons = config.defaultConfigs.eww.scriptButtons;
  scriptButtonNames = lib.attrNames scriptButtons;
  ewwExe = lib.getExe pkgs.eww;
  systemdRun = lib.getExe' pkgs.systemd "systemd-run";
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  spinnerSvg = pkgs.writeText "eww-spinner.svg" (
    builtins.replaceStrings [ "#ffffff" ] [ sxPalette.bone ] (builtins.readFile ./spinner.svg)
  );
  # The spinner shows while the condition is true.
  spinner =
    condition:
    ''(image :class "spinner" :path "${spinnerSvg}" :image-width 14 :image-height 14 :visible {${condition}})'';

  # This prints a JSON object, with true for each script that runs now.
  scriptsRunning = pkgs.writeShellApplication {
    name = "eww-scripts-running";
    runtimeInputs = [
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      names=(${lib.escapeShellArgs scriptButtonNames})
      # systemctl prints one state per unit, in the order of the arguments.
      mapfile -t states < <(systemctl --user is-active "''${names[@]/#/eww-button-}")
      jq -cn --argjson names ${lib.escapeShellArg (builtins.toJSON scriptButtonNames)} \
        '[$names, $ARGS.positional] | transpose | map({(.[0]): (.[1] == "active")}) | add' \
        --args "''${states[@]}"
    '';
  };
  refreshScriptsRunning = pkgs.writeShellScript "eww-refresh-scripts-running" ''
    ${ewwExe} update scripts_running="$(${lib.getExe scriptsRunning})"
  '';
  # The argument is the screen of the menu.
  scriptClick =
    name: button:
    pkgs.writeShellScript "eww-button-${name}-click" ''
      ${ewwExe} close "script-menu-$1"
      ${systemdRun} --user --quiet --collect --unit=eww-button-${name} \
        --property=ExecStopPost=${refreshScriptsRunning} \
        ${pkgs.writeShellScript "eww-button-${name}" button.command}
      ${refreshScriptsRunning}
    '';
  scriptMenuRow =
    name: button:
    let
      running = ''scripts_running["${name}"]'';
    in
    ''
      (button :class "script-menu-item ${name}" :onclick "${setsidPath} -f ${scriptClick name button} ''${screen}"
        (box :orientation "h" :space-evenly false :spacing 10
          (box :width 16
            ${spinner running}
            (label :text "${button.label}" :visible {!${running}}))
          (label :text "${button.text}")))
    '';
  # Eww cannot place a window below a widget. This distance from the right
  # edge of the screen puts the menu about below the menu button.
  scriptMenuOffset = "500px";
  anyScriptRunning = lib.concatMapStringsSep " || " (
    name: ''scripts_running["${name}"]''
  ) scriptButtonNames;
  scriptMenuDefinitions = lib.optionalString (scriptButtons != { }) ''
    (defvar scripts_running '${
      builtins.toJSON (lib.genAttrs scriptButtonNames (_: false))
    }')

    (defwindow script_menu [screen]
      :monitor screen
      :stacking "overlay"
      :geometry (geometry :x "${scriptMenuOffset}" :y "0px" :anchor "top right")
      (eventbox :onhoverlost "${setsidPath} -f ${ewwExe} close script-menu-''${screen}"
        (box :orientation "v" :space-evenly false
          ${lib.concatStrings (lib.mapAttrsToList scriptMenuRow scriptButtons)})))
  '';
  # The bar shows the stop button of a script only while the script runs.
  scriptStopButton =
    name: button:
    lib.optionalString (button.stopLabel != null) ''
      (button :class "script-stop-button ${name}" :tooltip "Stop: ${button.text}"
        :visible {scripts_running["${name}"]}
        :onclick "${setsidPath} -f ${systemctl} --user stop eww-button-${name}"
        (label :text "${button.stopLabel}"))
    '';
  scriptMenuButton = lib.optionalString (scriptButtons != { }) ''
    ${lib.concatStrings (lib.mapAttrsToList scriptStopButton scriptButtons)}
    (button :class "script-menu-button" :tooltip "Scripts"
      :onclick "${setsidPath} -f ${ewwExe} open --toggle --id script-menu-''${screen} --arg screen=''${screen} script_menu"
      (box
        ${spinner anyScriptRunning}
        (label :text "" :visible {!(${anyScriptRunning})})))
  '';

  yuckConfig =
    builtins.replaceStrings
      [
        "@WORKSPACES@"
        "@VOLUME@"
        "@VOLUME_STATE@"
        "@BATTERY@"
        "@BATTERY_CLASS@"
        "@STAY_AWAKE_CLICK@"
        "@FOCUS_WORKSPACE@"
        "@PAVUCONTROL@"
        "@POWER_PROFILE@"
        "@POWER_PROFILE_TOOLTIP@"
        "@POWER_PROFILE_CYCLE@"
        "@SUNSET_DEFINITION@"
        "@SUNSET_WIDGET@"
        "@SCRIPT_MENU_DEFINITIONS@"
        "@SCRIPT_MENU_BUTTON@"
        "@WORKSPACE_CLASS@"
      ]
      [
        (lib.getExe workspaceScript)
        (lib.getExe volume)
        "${lib.getExe volume} --state"
        (lib.getExe battery)
        "${lib.getExe battery} --class"
        "PATH=${stayAwakePath} ${setsidPath} -f stay-awake toggle"
        "${setsidPath} -f ${lib.getExe focusWorkspace}"
        "${setsidPath} -f ${lib.getExe pkgs.pavucontrol}"
        (lib.getExe powerProfile)
        "${lib.getExe powerProfile} --tooltip"
        "${setsidPath} -f ${lib.getExe cyclePowerProfile}"
        sunsetDefinition
        sunsetWidget
        scriptMenuDefinitions
        scriptMenuButton
        # The SXWM script computes the class, because it also marks away tags.
        (
          if sxwmEnabled then
            "{workspace.class}"
          else
            ''{workspace.active ? "workspace active" : "workspace"}''
        )
      ]
      (builtins.readFile ./eww.yuck);
  # Resolve palette tokens before Eww compiles the SCSS.
  scssConfig = builtins.replaceStrings
    [
      "@sx_carbon"
      "@sx_gunmetal"
      "@sx_graphite"
      "@sx_steel"
      "@sx_concrete"
      "@sx_bone"
      "@sx_caution"
      "@sx_go"
      "@sx_halt"
    ]
    [
      sxPalette.carbon
      sxPalette.gunmetal
      sxPalette.graphite
      sxPalette.steel
      sxPalette.concrete
      sxPalette.bone
      sxPalette.caution
      sxPalette.go
      sxPalette.halt
    ]
    (builtins.readFile ./eww.scss);
in
{
  options.defaultConfigs.eww = {
    enable = lib.mkEnableOption "the Eww bar configuration";
    scriptButtons = lib.mkOption {
      description = ''
        Scripts in the script menu. The bar shows the menu button left of the
        stay-awake button, and the stop buttons left of the menu button. The
        menu shows the scripts in the order of their names. The name sets the CSS class and the systemd unit
        (eww-button-<name>).
      '';
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              label = lib.mkOption {
                type = lib.types.str;
                description = "The icon of the menu row.";
              };
              text = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "The text of the menu row.";
              };
              command = lib.mkOption {
                type = lib.types.str;
                description = "The shell command that a click runs.";
              };
              stopLabel = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  If set, the bar shows a button with this label while the
                  script runs. A click on the button stops the script.
                '';
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf config.defaultConfigs.eww.enable {
    home.packages = [ pkgs.pavucontrol ];

    programs.eww = {
      inherit yuckConfig scssConfig;
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
