# To update: nix-update --file default.nix pi-coding-agent
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_20,
  nix-update-script,
  ...
}:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.52.7";

  # nodejs = nodejs_20;

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-+bx0N1gOlc3di0g7NcLTTTb3o0EE7MwKE3tfrCgCgNY=";
  };

  npmDepsHash = "sha256-YtXwi6ixHY/8++QiFHy9Q+FPi8vtVruDO7Gy6l37tuM=";

  npmWorkspace = "packages/coding-agent";

  npmRebuildFlags = [ "--ignore-scripts" ];

  buildPhase = ''
    runHook preBuild

    ./node_modules/.bin/tsgo -p packages/ai/tsconfig.build.json
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
