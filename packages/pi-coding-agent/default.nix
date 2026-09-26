# To update: nix run .#update-pi
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  nix-update-script,
  ...
}:

let
  version = "0.87.1";

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-GUhlq6t+l6iiViOZ0bkV28v3ZDqcLvEwpZpYZ5JAyDk=";
  };

  npmDepsHash = "sha256-JBIYoP2vvRNz1HONNvDJ1U3c+nmCJ7/VgNthRTkrkIA=";

  modelData = fetchzip {
    name = "pi-ai-model-data-${version}";
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha256-TC0jNS8xJj9aHfpFWgRi3eoz3eHz1m0+FoDYeQTo2iY=";
  };
in
buildNpmPackage rec {
  pname = "pi-coding-agent";
  inherit version src npmDepsHash;

  npmWorkspace = "packages/coding-agent";

  npmRebuildFlags = [ "--ignore-scripts" ];

  postPatch = ''
    mkdir -p packages/ai/src/providers/data
    cp -R ${modelData}/dist/providers/data/. packages/ai/src/providers/data/
  '';

  buildPhase = ''
    runHook preBuild

    npm run --workspace=packages/chord build
    npm run --workspace=packages/tui build
    npm run --workspace=packages/telemetry build
    npm run --workspace=packages/ai build:offline
    npm run --workspace=packages/agent build
    npm run --workspace=packages/session-backends/sqlite-node build
    npm run --workspace=packages/protocol build
    npm run --workspace=packages/client build
    npm run --workspace=packages/server build
    npm run --workspace=packages/coding-agent build

    runHook postBuild
  '';

  postInstall = ''
    workspace_out="$out/lib/node_modules/pi-monorepo/packages"
    mkdir -p "$workspace_out"

    cp -R packages/. "$workspace_out"
  '';

  passthru = {
    inherit modelData;
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--custom-dep"
        "modelData"
        "--build"
      ];
    };
  };

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://github.com/badlogic/pi-mono";
    downloadPage = "https://www.npmjs.com/package/@mariozechner/pi-coding-agent";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
