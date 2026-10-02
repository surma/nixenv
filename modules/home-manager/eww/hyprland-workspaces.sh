emit_workspaces() {
  local workspaces monitors
  workspaces="$(hyprctl -j workspaces)"
  monitors="$(hyprctl -j monitors)"

  jq -cn --argjson workspaces "$workspaces" --argjson monitors "$monitors" '
    [
      $workspaces[]
      | select(.id > 0)
      | . as $workspace
      | $monitors[]
      | select(.name == $workspace.monitor)
      | {
          id: $workspace.id,
          index: $workspace.id,
          label: (
            if $workspace.id >= 1 and $workspace.id <= 9 then
              ($workspace.id | tostring)
            elif $workspace.id >= 10 and $workspace.id <= 35 then
              ([$workspace.id + 55] | implode)
            else
              ($workspace.name // ($workspace.id | tostring))
            end
          ),
          output: $workspace.monitor,
          active: (.activeWorkspace.id == $workspace.id)
        }
    ]
    | sort_by(.id)
  '
}

emit_workspaces

socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -u "UNIX-CONNECT:$socket" - | while IFS= read -r event; do
  event_type="${event%%>>*}"
  case "$event_type" in
    workspace|workspacev2|focusedmon|focusedmonv2|createworkspace|createworkspacev2|destroyworkspace|destroyworkspacev2|moveworkspace|moveworkspacev2|renameworkspace|renameworkspacev2)
      emit_workspaces
      ;;
  esac
done
