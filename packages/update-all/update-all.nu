#!/usr/bin/env nu

def nix-update-args [pkg] {
  let name = $pkg.name
  let extra_args = ($pkg | get -o nix_update_args | default [])
  [ "--flake" $name ] | append $extra_args
}

def main [] {
  let root = (^git rev-parse --show-toplevel | str trim)
  if ($root | is-empty) {
    print "Error: unable to determine git root."
    exit 1
  }

  cd $root

  let fsmonitor_value = (try { ^git config --local --get core.fsmonitor | str trim } catch { "" })
  let fsmonitor_was_set = (not ($fsmonitor_value | is-empty))

  print "Disabling git fsmonitor..."
  ^git config --local core.fsmonitor false
  try { ^git fsmonitor--daemon stop } catch { }
  if (".git/fsmonitor--daemon.ipc" | path exists) {
    ^rm -f .git/fsmonitor--daemon.ipc
  }

  print "Updating flake inputs..."
  let github_token = ($env.GITHUB_TOKEN? | default ($env.GH_TOKEN?))
  if $github_token == null {
    ^nix flake update
  } else {
    ^nix flake update --option access-tokens $"github.com=($github_token)"
  }

  if (".git/fsmonitor--daemon.ipc" | path exists) {
    ^rm -f .git/fsmonitor--daemon.ipc
  }

  let packages = [
    { name: "pi-coding-agent" nix_update_args: [ "--custom-dep" "modelData" ] }
    { name: "handy" }
    { name: "agent-browser" }
    { name: "pi-acp" }
    { name: "tinycast" }
  ]

  mut failed_packages = []
  for pkg in $packages {
    if (".git/fsmonitor--daemon.ipc" | path exists) {
      ^rm -f .git/fsmonitor--daemon.ipc
    }

    let name = $pkg.name
    print $"Updating ($name)..."

    let args = (nix-update-args $pkg)
    let updated = (try {
      ^nix run nixpkgs#nix-update -- ...$args
      if $name == "pi-coding-agent" {
        print "Building pi-coding-agent..."
        ^nix build ".#pi-coding-agent" --no-link
      }
      true
    } catch { |err|
      let message = ($err.msg? | default "unknown error")
      print $"Warning: update for ($name) failed: ($message)"
      false
    })
    if not $updated {
      $failed_packages = ($failed_packages | append $name)
    }
  }

  print "Updating tailscale addresses in ips.nix..."
  try {
    ^nix run $".#tailscale-ips-update" -- --ips-file ips.nix
  } catch { |err|
    let message = ($err.msg? | default "unknown error")
    print $"Warning: tailscale address update failed: ($message)"
  }

  if $fsmonitor_was_set {
    ^git config --local core.fsmonitor $fsmonitor_value
  } else {
    try { ^git config --local --unset core.fsmonitor } catch { }
  }

  if not ($failed_packages | is-empty) {
    error make { msg: $"Package updates failed: ($failed_packages | str join ', ')" }
  }
}
