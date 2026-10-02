format_workspaces() {
  jq -c '
    sort_by([.output // "", .idx])
    | map({
        id,
        index: .idx,
        output,
        label: (.name // (.idx | tostring)),
        active: .is_active
      })
  '
}

if [[ ${1:-} == --format ]]; then
  format_workspaces
  exit
fi

niri msg --json event-stream | while IFS= read -r event; do
  if jq -e 'has("WorkspacesChanged") or has("WorkspaceActivated")' >/dev/null <<< "$event"; then
    niri msg --json workspaces | format_workspaces
  fi
done
