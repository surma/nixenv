#!/usr/bin/env nu

def main [
  msg: string
  --name: string  # Optional session/context name
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
    ^/usr/bin/osascript -e $"display notification ($msg | to json) with title ($session_name | to json)" | complete | ignore
  } else {
    ^notify-send $session_name $msg | complete | ignore
  }
}
