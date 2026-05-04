#!/usr/bin/env nu

def "main local" [
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

  if $os == "Darwin" {
    let sound_param = if $chime { " sound name \"Glass\"" } else { "" }
    ^/usr/bin/osascript -e $"display notification ($msg | to json) with title ($session_name | to json)($sound_param)" | complete | ignore
  } else {
    let urgency_flag = if $chime { ["-u" "critical"] } else { [] }
    ^notify-send ...$urgency_flag $session_name $msg | complete | ignore
  }
}

def "main mobile" [
  msg: string
  --name: string    # Optional session/context name
  --device: string  # HA mobile device name (default: $env.NOTI_MOBILE_DEVICE)
] {
  let session_name = if ($name | is-not-empty) {
    $name
  } else if ($env.ZELLIJ_SESSION_NAME? | is-not-empty) {
    $env.ZELLIJ_SESSION_NAME
  } else {
    "unknown session"
  }

  let target_device = if ($device | is-not-empty) {
    $device
  } else {
    $env.NOTI_MOBILE_DEVICE? | default ""
  }

  if ($target_device | is-empty) {
    error make { msg: "No device specified. Use --device or set NOTI_MOBILE_DEVICE." }
  }

  let payload = { message: $msg, title: $session_name } | to json
  ^hassio call-service notify $"mobile_app_($target_device)" -d $payload | complete | ignore
}

def main [] {
  print "Usage: noti <local|mobile> <message>"
  print ""
  print "Subcommands:"
  print "  local   Send an OS notification (macOS/Linux)"
  print "  mobile  Send a push notification via Home Assistant"
}
