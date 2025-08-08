{
  ...
}:
final: prev:
let
  # nixpkgs-unstable @ Aug 6, 2025
  nixpkgs-unstable-rev = {
    owner = "nixos";
    repo = "nixpkgs";
    rev = "cab778239e705082fe97bb4990e0d24c50924c04";
    hash = "sha256-lgmUyVQL9tSnvvIvBp7x1euhkkCho7n3TMzgjdvgPoU=";
  };
  pkgs-unstable = import (fetchFromGitHub nixpkgs-unstable-rev) { inherit system; };

  inherit (prev) fetchFromGitHub system;
in
{
  inherit (pkgs-unstable)
    gdb
    zig
    zls
    just
    dprint
    ollama
    podman
    zellij
    wezterm
    wasmtime
    qbittorrent
    aerospace
    karabiner-elements
    podman-compose
    ;
}
