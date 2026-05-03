#!/usr/bin/env nu

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

  let claude_version = (try {
    let claude_cask = (http get --raw https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/c/claude-code.rb | into string)
    let claude_version_lines = (
      $claude_cask
      | lines
      | where { |line| $line | str contains 'version "' }
    )
    if ($claude_version_lines | is-empty) {
      null
    } else {
      $claude_version_lines
      | first
      | parse -r 'version "(?<version>[^"]+)"'
      | get 0.version
    }
  } catch { null })
  if $claude_version == null {
    print "Warning: could not determine claude-code version from Homebrew cask."
  }

  let surm_auth_version = (try {
    let surm_auth_version_lines = (
      open packages/surm-auth/default.nix
      | lines
      | where { |line| $line | str contains 'version = "' }
    )
    if ($surm_auth_version_lines | is-empty) {
      null
    } else {
      $surm_auth_version_lines
      | first
      | parse -r 'version = "(?<version>[^"]+)"'
      | get 0.version
    }
  } catch { null })
  if $surm_auth_version == null {
    print "Warning: could not determine surm-auth version from packages/surm-auth/default.nix."
  }

  let packages = [
    { name: "pi-coding-agent" }
    { name: "handy" }
    { name: "claude-code" version: $claude_version requires_version: true }
    { name: "surm-auth" version: $surm_auth_version requires_version: true }
    { name: "agent-browser" }
    { name: "homeassistant-cli" }
    { name: "pi-acp" }
    { name: "rtk" }
  ]

  for pkg in $packages {
    if (".git/fsmonitor--daemon.ipc" | path exists) {
      ^rm -f .git/fsmonitor--daemon.ipc
    }

    let name = $pkg.name
    print $"Updating ($name)..."

    let version = ($pkg | get -o version)
    let requires_version = ($pkg | get -o requires_version | default false)
    if $requires_version and $version == null {
      print $"Warning: skipping ($name) update because version could not be determined."
      continue
    }

    try {
      if $version == null {
        ^nix run nixpkgs#nix-update -- --flake $name
      } else {
        ^nix run nixpkgs#nix-update -- --flake $name --version $version
      }
    } catch { |err|
      let message = ($err.msg? | default "unknown error")
      print $"Warning: update for ($name) failed: ($message)"
    }
  }

  if $fsmonitor_was_set {
    ^git config --local core.fsmonitor $fsmonitor_value
  } else {
    try { ^git config --local --unset core.fsmonitor } catch { }
  }
}
