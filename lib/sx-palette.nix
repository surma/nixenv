# T22 moves this JSON into the sx input.
{ inputs }:
builtins.fromJSON (builtins.readFile ./palette.json)
