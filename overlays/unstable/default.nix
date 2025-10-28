{
  ...
}:
final: prev:
let
  # nixpkgs-unstable @ Oct 6, 2025
  nixpkgs-unstable-rev = {
    owner = "nixos";
    repo = "nixpkgs";
    rev = "e52bb03cd8997f19c106f94602ecd503784883b0";
    hash = "sha256-0gpUKn1cW7S6kp4b0d9zdXth4JJHGFV6cnsQ9Lo3PyY=";
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
    sonarr
    radarr
    librespot
    ;
}
