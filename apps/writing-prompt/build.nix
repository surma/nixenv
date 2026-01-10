{
  lib,
  nix-gitignore,
  buildNpmPackage,
}:
let
  src = builtins.fetchGit {
    url = "ssh://git@github.com/surma/writing-prompt";
    ref = "main";
    rev = "5eecd857b59c46e90dc22b740cdc865310d5ec34";
  };
  packageJson = "${src}/package.json" |> lib.importJSON;
in
buildNpmPackage {
  pname = packageJson.name;
  version = packageJson.version;
  inherit src;

  npmDepsHash = "sha256-Y2Tsotr1Ag9K0RLLjWEplOr0jAM8kMsAPVtMT5F4iLQ=";
}
