# To update: nix-update --file default.nix pi-coding-agent
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  nix-update-script,
  ...
}:

let
  version = "0.84.1";

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-lg+I4S/aAjazjhGZU567ow+rksoNiqOqjHl//TjAMes=";
  };

  npmDepsHash = "sha256-vz5+zzzXMrIgO43oluJwA2kTGLmyKjyda06oYryOfAM=";

  modelData = fetchzip {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha256-OpiG7u0hptGZRnwhSlB6jbA1iNHd71zBXrDEERrpQTg=";
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

    npm run --workspace=packages/ai build:offline
    npm run --workspace=packages/agent build
    npm run --workspace=packages/tui build
    npm run --workspace=packages/coding-agent build

    runHook postBuild
  '';

  postInstall = ''
    workspace_out="$out/lib/node_modules/pi-monorepo/packages"
    mkdir -p "$workspace_out"

    cp -R packages/. "$workspace_out"
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://github.com/badlogic/pi-mono";
    downloadPage = "https://www.npmjs.com/package/@mariozechner/pi-coding-agent";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
