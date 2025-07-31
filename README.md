# home-manager-config

## Installation

### Install nix

(remove `--daemon` on MacOS)

```sh
$ sh <(curl -L https://nixos.org/nix/install) --daemon
```
### Install home-assistant

```
# MacOS
$ nix --extra-experimental-features 'nix-command flakes' \
  run 'github:LnL7/nix-darwin' -- \
  --extra-experimental-features 'nix-command flakes' \
  switch --flake 'github:surma/home-manager-config#generic-macos'

# Linux
$ nix --extra-experimental-features 'nix-command flakes' \
  run 'github:nix-community/home-manager' -- \
  --extra-experimental-features 'nix-command flakes' \
  -b backup \
  switch --flake 'github:surma/home-manager-config#generic-linux'

# Android
$ nix --extra-experimental-features 'nix-command flakes' \
  run 'github:nix-community/nix-on-droid' -- \
  switch --flake 'github:surma/home-manager-config#generic-android'
```

