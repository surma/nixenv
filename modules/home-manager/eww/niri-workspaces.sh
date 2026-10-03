format_workspaces() {
  # Named workspaces always exist, so show a workspace only when it has a
  # window or is the active one on its output. Unnamed workspaces sit below
  # the named ones and are numbered from 1 per output.
  jq -c '
    sort_by([.output // "", .idx])
    | . as $all
    | map(
        . as $ws
        | select(.active_window_id != null or .is_active)
        | {
            id,
            index: .idx,
            output,
            label: (
              .name
              // ([$all[] | select(.output == $ws.output and .name == null and .idx <= $ws.idx)]
                | length
                | tostring)
            ),
            active: .is_active
          }
      )
  '
}

if [[ ${1:-} == --format ]]; then
  format_workspaces
  exit
fi

niri msg --json event-stream | while IFS= read -r event; do
  if jq -e 'has("WorkspacesChanged") or has("WorkspaceActivated") or has("WorkspaceActiveWindowChanged")' >/dev/null <<< "$event"; then
    niri msg --json workspaces | format_workspaces
  fi
done
