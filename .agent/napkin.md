# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-11 | self | Started work before reading .agent/napkin.md, violating the napkin skill's first-step requirement. | Read .agent/napkin.md before any other action at session start. |
| 2026-02-11 | self | Started multi-step work without creating a todo list as required by the pi-superpowers skill. | Create a todo list before multi-step changes to track progress. |
| 2026-02-07 | self | Changed only the cancellation message instead of aligning the cancel path with the same rejection handler as the "No" selection. | When asked to unify behaviors, share the exact helper path (state updates + response) so both cases are truly identical. |

## User Preferences
- (accumulate here as you learn them)

## Patterns That Work
- (approaches that succeeded)

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- Plan mode extension (`modules/programs/pi/extensions/plan-mode/claude-plan-mode.ts`) queues `/plan accept` via `pi.sendUserMessage`, but sendUserMessage bypasses command handling, so the command never runs and `ctx.newSession()` is not triggered. This explains context not clearing after plan acceptance.
