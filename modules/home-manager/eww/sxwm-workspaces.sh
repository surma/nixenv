format_workspaces() {
  # Each bar shows the tags that are active on its screen, and the tags that
  # have windows but are active on no screen. Tags that are active on another
  # screen appear on that screen's bar. The index is the tag ID, so that a
  # click can toggle or focus the tag.
  jq -c '
    .tags as $tags
    | [
        .screens[] as $screen
        | $tags[]
        | select(.screen == $screen.id or (.screen == null and (.windows | length) > 0))
        | {
            id,
            index: .id,
            output: $screen.id,
            label: .name,
            active: (.screen == $screen.id)
          }
      ]
  '
}

if [[ ${1:-} == --format ]]; then
  format_workspaces
  exit
fi

sxwmctl --watch --initial tag.changed screen.added screen.changed screen.removed \
  | while IFS= read -r _; do
      sxwmctl state.get | format_workspaces
    done
