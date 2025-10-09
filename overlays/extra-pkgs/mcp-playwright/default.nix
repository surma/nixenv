{
  buildNpmPackage,
  lsof,
  lib,
  makeWrapper,
  writeShellScriptBin,
  nodejs ? args.nodejs_24,
  importNpmLock,
  ...
}@args:
let
  src = ./.;
  packageJson = lib.importJSON "${src}/package.json";

  nodeBundle = buildNpmPackage {
    pname = "mcp-playwright";
    version = packageJson.version;

    nativeBuildInputs = [ makeWrapper ];

    dontNpmBuild = true;
    inherit src nodejs;
    npmDeps = importNpmLock {
      npmRoot = src;
    };

    npmConfigHook = importNpmLock.npmConfigHook;
  };
in
writeShellScriptBin "mcp-playwright" ''
  PATH=$PATH:${lib.makeBinPath [ lsof ]}

  node ${nodeBundle}/lib/node_modules/${packageJson.name}/node_modules/.bin/mcp-server-playwright "$@"
''
