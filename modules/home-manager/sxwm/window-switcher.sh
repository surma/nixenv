# List the open windows in fuzzel and focus the selected one. SXWM lists
# windows in stack order, front first. The focused window goes last, so Enter
# goes to the window in front of the others.
windows="$(sxwmctl state.get | jq '.windows | sort_by(.focused)')"

index="$(
  jq -r '.[] | "\(.title // "") — \(.app_id // "")\u0000icon\u001f\(.app_id // "")"' <<< "$windows" \
    | fuzzel --dmenu --index --prompt "window> "
)"

id="$(jq -r --argjson index "$index" '.[$index].id' <<< "$windows")"
sxwmctl windows.focus "{\"window\": $id}"
