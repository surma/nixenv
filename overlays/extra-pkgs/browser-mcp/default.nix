{
  buildNpmPackage,
  lsof,
  lib,
  makeWrapper,
  writeShellScriptBin,
  nodejs ? args.nodejs_24,
}@args:
let
  src = ./.;
  packageJson = lib.importJSON "${src}/package.json";

  nodeBundle = buildNpmPackage {
    pname = "browser-mcp";
    version = packageJson.version;

    nativeBuildInputs = [ makeWrapper ];

    dontNpmBuild = true;
    inherit src nodejs;
    npmDepsHash = "sha256-ZVUHpr9X8+tQEyOrQTnmfe4v2M/G4+kJKXx30ESHanE=";
  };
in
writeShellScriptBin "browser-mcp" ''
  PATH=$PATH:${lib.makeBinPath [ lsof ]}

  node ${nodeBundle}/lib/node_modules/${packageJson.name}/node_modules/.bin/mcp-server-browsermcp "$@"
''
