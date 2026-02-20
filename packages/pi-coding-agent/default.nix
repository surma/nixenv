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
  version = "0.54.0";

  # nodejs = nodejs_20;

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-j8h8KKt/1m47Y6/KA8g213gooq0n2fAqBVkKhHsBCGw=";
  };

  npmDepsHash = "sha256-L2kP2VpRNg+YeZjvXyn+Soly2wlff4jpZ5qa3T43quE=";

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
