#!/usr/bin/env nu

# This script runs for the Eww approve-PRs button.
# A pi session approves the new PRs from the DMs with Christian.
# A desktop notification shows the output of pi.

def main [
  --session: string = "01a0aeb4-6823-7403-b366-b048eb89a90f" # pi session ID
  --prompt: string = "approve all PRs since the last one you have seen in DMs with Christian" # prompt for pi
] {
  # Pi looks for the session in the project of the working directory.
  cd ~/world/trees/root/src
  # The interactive zsh loads the Shopify toolchain (devx, gs, agent-tools).
  let result = (^zsh -ic 'exec devx pi --offline --session "$1" -p "$2"' zsh $session $prompt | complete)
  if $result.exit_code == 0 {
    ^notify-send "Approve PRs" ($result.stdout | str trim)
  } else {
    # The interactive zsh writes warnings to stderr first.
    # The journal gets all of stderr, and the notification shows the last line.
    print --stderr $result.stderr
    ^notify-send --urgency=critical "Approve PRs failed" ($result.stderr | str trim | lines | last)
  }
}
