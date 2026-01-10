{
  lib,
  nix-gitignore,
  python3,
  buildNpmPackage,
  importNpmLock,
}:
let
  src = builtins.fetchGit {
    url = "ssh://git@github.com/surma/hate";
    ref = "main";
    rev = "1974d70564282b7abd983ff66c95bb99e718a03d";
  };
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
