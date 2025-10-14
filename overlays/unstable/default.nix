{
  ...
}:
final: prev:
let
  # nixpkgs-unstable @ Oct 6, 2025
  nixpkgs-unstable-rev = {
    owner = "nixos";
    repo = "nixpkgs";
    rev = "d7f52a7a640bc54c7bb414cca603835bf8dd4b10";
    hash = "sha256-krgZxGAIIIKFJS+UB0l8do3sYUDWJc75M72tepmVMzE=";
  };
  pkgs-unstable = import (fetchFromGitHub nixpkgs-unstable-rev) { inherit system; };

  inherit (prev) fetchFromGitHub system;
in
{
  inherit (pkgs-unstable)
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
    nushell
    prowlarr
    lidarr
    librespot
    ;
}
