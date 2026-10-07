format_workspaces() {
  # Each bar shows the tags whose home is its screen and the tags that are
  # active on it. A tag shows only when it is active somewhere or has windows.
  # A home tag that is active on another screen is "away": its home bar shows
  # it grayed out. A tag with a window that requests attention is "urgent".
  # The index is the tag ID, so that a click can switch to it.
  jq -c '
    .tags as $tags
    | .windows as $windows
    | [
        .screens[] as $screen
        | $tags[]
        | . as $tag
        | select(.screen != null or (.windows | length) > 0)
        | select(.home == $screen.id or .screen == $screen.id)
        | {
            id,
            index: .id,
            output: $screen.id,
            label: .name,
            active: (.screen == $screen.id),
            class: (
              (if .screen == $screen.id then "workspace active"
               elif .screen != null then "workspace away"
               else "workspace" end)
              + (if any($windows[]; .tag == $tag.id and .urgent) then " urgent" else "" end)
            )
          }
      ]
  '
}

if [[ ${1:-} == --format ]]; then
  format_workspaces
  exit
fi

sxwmctl --watch --initial tag.changed window.changed screen.added screen.changed screen.removed \
  | while IFS= read -r _; do
      sxwmctl state.get | format_workspaces
    done
