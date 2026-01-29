{ lib, inputs, ... }:
{
  perSystem = { pkgs, system, config, ... }:
    let
      packagesDir = ../../packages;
      packageDirs = builtins.readDir packagesDir;
    in
    {
      packages =
        lib.filterAttrs (n: v: v == "directory") packageDirs
        |> lib.mapAttrs (name: _: pkgs.callPackage (packagesDir + "/${name}") { inherit inputs; });
    };
}
