#!/usr/bin/env nu

def require-env [name: string] {
  let value = ($env | get -o $name | default "")

  if ($value | is-empty) {
    error make { msg: $"nixenvupdate: ($name) is not set" }
  }

  $value
}

def command-path [name: string] {
  which $name | get 0.path
}

def build-target [target: string, out_link: string, refresh: bool] {
  print $"Building ($target)"
  let refresh_args = if $refresh { [--refresh] } else { [] }
  nix build ...$refresh_args $target --out-link $out_link
  readlink -f $out_link | str trim
}

def activate-nixos [system_path: string] {
  print $"Activating NixOS system ($system_path)"
  let nix_env = (command-path nix-env)
  run-external sudo $nix_env "-p" /nix/var/nix/profiles/system "--set" $system_path
  let switch_to_configuration = ([$system_path bin switch-to-configuration] | path join)
  run-external sudo $switch_to_configuration switch
}

def darwin-activate-user-is-deprecated [activate_user: string] {
  open $activate_user | lines | any { |line| $line == "# nix-darwin: deprecated" }
}

def activate-darwin [system_path: string] {
  let profile = ($env.NIXENV_DARWIN_PROFILE? | default /nix/var/nix/profiles/system)

  print $"Activating nix-darwin system ($system_path)"
  let nix_env = (command-path nix-env)
  run-external sudo $nix_env "-p" $profile "--set" $system_path

  let activate_user = ([$system_path activate-user] | path join)
  if (($activate_user | path exists) and not (darwin-activate-user-is-deprecated $activate_user)) {
    run-external $activate_user
  }

  let activate = ([$system_path activate] | path join)
  run-external sudo $activate
}

def home-manager-profile-dir [] {
  let state_home = ($env.XDG_STATE_HOME? | default ([$env.HOME .local state] | path join))
  let user_profiles = ([$state_home nix profiles] | path join)
  let global_profiles = ([($env.NIX_STATE_DIR? | default /nix/var/nix) profiles per-user $env.USER] | path join)

  if ($user_profiles | path exists) {
    return $user_profiles
  }

  if ($global_profiles | path exists) {
    return $global_profiles
  }

  error make {
    msg: $"nixenvupdate: could not find a Home Manager profile directory\ntried: ($user_profiles)\ntried: ($global_profiles)"
  }
}

def activate-home-manager [generation_path: string] {
  let profile_dir = (home-manager-profile-dir)
  let profile = ([$profile_dir home-manager] | path join)

  print $"Activating Home Manager generation ($generation_path)"
  nix-env --profile $profile --set $generation_path

  let activate = ([$generation_path activate] | path join)
  run-external $activate "--driver-version" "1"
}

def main [
  --flake: string # Flake ref to build. Defaults to $NIXENV_FLAKE_REF or github:surma/nixenv.
  --build-only # Build the target generation, but do not activate it.
  --refresh # Ask Nix to refresh flakes and other cached remote inputs before building.
] {
  let flake_ref = if $flake == null {
    $env.NIXENV_FLAKE_REF? | default github:surma/nixenv
  } else {
    $flake
  }
  let machine_name = (require-env NIXENV_MACHINE_NAME)
  let config_kind = (require-env NIXENV_CONFIG_KIND)

  if not ($machine_name =~ '^[A-Za-z0-9._-]+$') {
    error make { msg: $"nixenvupdate: unsupported machine name: ($machine_name)" }
  }

  let workdir = (mktemp -d -t nixenvupdate.XXXXXXXXXX | str trim)
  let out_link = ([$workdir result] | path join)

  let built_path = match $config_kind {
    nixos => {
      build-target $"($flake_ref)#nixosConfigurations.($machine_name).config.system.build.toplevel" $out_link $refresh
    }
    darwin | nix-darwin | macos => {
      build-target $"($flake_ref)#darwinConfigurations.($machine_name).system" $out_link $refresh
    }
    home-manager | home => {
      build-target $"($flake_ref)#homeConfigurations.($machine_name).activationPackage" $out_link $refresh
    }
    _ => {
      error make { msg: $"nixenvupdate: unsupported NIXENV_CONFIG_KIND: ($config_kind)" }
    }
  }

  if $build_only {
    print $"Built ($built_path)"
    rm -rf $workdir
    return
  }

  match $config_kind {
    nixos => { activate-nixos $built_path }
    darwin | nix-darwin | macos => { activate-darwin $built_path }
    home-manager | home => { activate-home-manager $built_path }
  }

  rm -rf $workdir
}
