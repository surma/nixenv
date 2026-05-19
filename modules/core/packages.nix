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
    in
    {
      packages =
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (packagesDir + "/${name}/default.nix")
        ) packageDirs
        |> lib.mapAttrs (name: _: pkgs.callPackage (packagesDir + "/${name}") { inherit inputs; });
    };
}
