#!/usr/bin/env nu

def main [
  msg: string
  --name: string  # Optional session/context name
  --chime         # Play a sound with the notification
] {
  let os = (sys host | get name)
  
  # Get session name from flag, environment, or default to "unknown session"
  let session_name = if ($name | is-not-empty) {
    $name
  } else if ($env.ZELLIJ_SESSION_NAME? | is-not-empty) {
    $env.ZELLIJ_SESSION_NAME
  } else {
    "unknown session"
  }
  
  # Send notification and swallow all output
  if $os == "Darwin" {
    let sound_param = if $chime { " sound name \"Glass\"" } else { "" }
    ^/usr/bin/osascript -e $"display notification ($msg | to json) with title ($session_name | to json)($sound_param)" | complete | ignore
  } else {
    let urgency_flag = if $chime { ["-u" "critical"] } else { [] }
    ^notify-send ...$urgency_flag $session_name $msg | complete | ignore
  }
}
