{
  buildNpmPackage,
  lib,
  makeWrapper,
  writeShellScriptBin,
  nodejs ? args.nodejs_24,
}@args:
let
  src = ./.;
  packageJson = lib.importJSON "${src}/package.json";

  nodeBundle = buildNpmPackage {
    pname = packageJson.name;
    version = packageJson.version;

    nativeBuildInputs = [ makeWrapper ];

    dontNpmBuild = true;
    inherit src nodejs;
    npmDepsHash = "sha256-uVLKA4wb1H86udE7un5xjAmKZNX5rNOdP2rTHdZ6leg=";
  };
in
writeShellScriptBin "claude" ''
  node ${nodeBundle}/lib/node_modules/${packageJson.name}/node_modules/.bin/claude "$@"
''
