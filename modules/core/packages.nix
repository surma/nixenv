{ lib, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      config,
      ...
    }:
    let
      packagesDir = ../../packages;
      packageDirs = builtins.readDir packagesDir;
      packages =
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (packagesDir + "/${name}/default.nix")
        ) packageDirs
        |> lib.mapAttrs (name: _: pkgs.callPackage (packagesDir + "/${name}") { inherit inputs; });
    in
    {
      packages = lib.filterAttrs (
        _: package: lib.meta.availableOn pkgs.stdenv.hostPlatform package
      ) packages;
    };
}
