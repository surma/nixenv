{
  lib,
  nix-gitignore,
  python3,
  buildNpmPackage,
  importNpmLock,
}:
let
  src = nix-gitignore.gitignoreSource [ ] ./repo;
  packageJson = "${src}/package.json" |> lib.importJSON;
in
buildNpmPackage {
  pname = packageJson.name;
  version = packageJson.version;
  inherit src;

  buildInputs = [ python3 ];

  npmDeps = importNpmLock { npmRoot = src; };

  npmConfigHook = importNpmLock.npmConfigHook;
}
