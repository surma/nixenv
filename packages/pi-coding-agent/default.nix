# To update: nix-update --file default.nix pi-coding-agent
{
  lib,
  buildNpmPackage,
  cacert,
  fetchFromGitHub,
  nix-update-script,
  ...
}:

let
  version = "0.82.1";

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-LESpgd/KUoNqdBfnd1oyMN8coKm0Odbo9GYkUDry8Zk=";
  };

  npmDepsHash = "sha256-5pHRwxpKg95/phOcYHeWdvPJNtSOhiw7PRoVxsuh0RM=";

  modelData = buildNpmPackage {
    pname = "pi-coding-agent-model-data";
    inherit version src npmDepsHash;

    npmWorkspace = "packages/ai";
    npmRebuildFlags = [ "--ignore-scripts" ];
    NODE_EXTRA_CA_CERTS = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    # Upstream writes the current time, which cannot vary in a fixed-output derivation.
    postPatch = ''
      substituteInPlace packages/ai/scripts/generate-models.ts \
        --replace-fail \
          'const generatedAt = new Date().toISOString();' \
          'const generatedAt = "1970-01-01T00:00:00.000Z";'
    '';

    dontNpmBuild = true;
    buildPhase = ''
      runHook preBuild

      npm run --workspace=packages/ai hydrate-model-data
      npm run --workspace=packages/ai check:model-data

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R packages/ai/src/providers/data/. "$out/"
      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHash = "sha256-68cthreBIgwJAwjPd1Ma/EaoueLMdrb80402IGI8l48=";
  };
in
buildNpmPackage rec {
  pname = "pi-coding-agent";
  inherit version src npmDepsHash;

  npmWorkspace = "packages/coding-agent";

  npmRebuildFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp -R ${modelData}/. packages/ai/src/providers/data/
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
