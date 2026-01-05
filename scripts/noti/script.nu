#!/usr/bin/env nu

def main [
  msg: string
] {
  let os = (sys host | get name)

  if $os == "Darwin" {
    osascript -e $"display notification ($msg | to json)"
  } else {
    notify-send "Notification" $msg
  }
}
