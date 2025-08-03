{
  ...
}:
final: prev:
let
  # nixpkgs-unstable @ Jun 15, 2025
  nixpkgs-unstable-rev = {
    owner = "nixos";
    repo = "nixpkgs";
    rev = "41da1e3ea8e23e094e5e3eeb1e6b830468a7399e";
    hash = "sha256-jp0D4vzBcRKwNZwfY4BcWHemLGUs4JrS3X9w5k/JYDA=";
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
