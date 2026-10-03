# List the open windows in fuzzel and focus the selected one. The focused
# window goes last and the others follow the order of last focus, so Enter
# goes to the previous window.
windows="$(
  niri msg --json windows | jq '
    sort_by([
      .is_focused,
      -((.focus_timestamp.secs // 0) + (.focus_timestamp.nanos // 0) / 1e9)
    ])
  '
)"

index="$(
  jq -r '.[] | "\(.title) — \(.app_id)\u0000icon\u001f\(.app_id)"' <<< "$windows" \
    | fuzzel --dmenu --index --prompt "window> "
)"

id="$(jq -r --argjson index "$index" '.[$index].id' <<< "$windows")"
niri msg action focus-window --id "$id"
