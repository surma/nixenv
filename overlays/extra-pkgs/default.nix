{
  inputs,
  ...
}:
final: prev:
let
  inherit (prev) callPackage lib;

  extraPkgsSrc = ./.;
  extraPkgs = builtins.readDir extraPkgsSrc;
in
extraPkgs
|> lib.filterAttrs (name: value: value == "directory")
|> lib.mapAttrs (name: value: callPackage (import "${extraPkgsSrc}/${name}") { inherit inputs; })
