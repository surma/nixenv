#!/usr/bin/env nu

def current-zellij-pane [] {
  let pane_id = ($env.ZELLIJ_PANE_ID? | default "")
  if ($pane_id | is-empty) {
    return null
  }

  let pane_id_num = try {
    $pane_id | str replace --regex '^(terminal_|plugin_)' '' | into int
  } catch {
    return null
  }

  let result = try {
    ^zellij action list-panes --all --json | complete
  } catch {
    return null
  }

  if $result.exit_code != 0 {
    return null
  }

  let panes = try {
    $result.stdout | from json
  } catch {
    return null
  }

  $panes | where id == $pane_id_num | first
}

def zellij-tab-name [] {
  let pane = (current-zellij-pane)
  if $pane == null {
    return ""
  }

  $pane.tab_name? | default ""
}

def alert-zellij-tab [] {
  if (($env.ZELLIJ? | is-empty) and ($env.ZELLIJ_PANE_ID? | is-empty)) {
    return
  }

  # Prefer the controlling TTY so the BEL still reaches Zellij when stdout is captured.
  try {
    (char bel) | save --raw --force /dev/tty
  } catch {
    print -n (char bel)
  }
}

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

  let tab_name = (zellij-tab-name)
  let notification_title = if ($tab_name | is-not-empty) {
    $"($session_name) · ($tab_name)"
  } else {
    $session_name
  }

  alert-zellij-tab

  if $os == "Darwin" {
    let sound_param = if $chime { " sound name \"Glass\"" } else { "" }
    ^/usr/bin/osascript -e $"display notification ($msg | to json) with title ($notification_title | to json)($sound_param)" | complete | ignore
  } else {
    let urgency_flag = if $chime { ["-u" "critical"] } else { [] }
    ^notify-send ...$urgency_flag $notification_title $msg | complete | ignore
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
  let result = ^hassio call-service notify $"mobile_app_($target_device)" -d $payload | complete
  if $result.exit_code != 0 {
    let details = ($result.stderr | str trim)
    let error_msg = if ($details | is-empty) {
      $"hassio notification failed with exit code ($result.exit_code)"
    } else {
      $"hassio notification failed with exit code ($result.exit_code): ($details)"
    }
    error make { msg: $error_msg }
  }
}

def main [] {
  print "Usage: noti <local|mobile> <message>"
  print ""
  print "Subcommands:"
  print "  local   Send an OS notification (macOS/Linux)"
  print "  mobile  Send a push notification via Home Assistant"
}
