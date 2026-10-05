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
  version = "1.0.4";

  src = fetchFromGitHub {
    owner = "badlogic";
    repo = "pi-mono";
    tag = "v${version}";
    hash = "sha256-twDmQRr7vsrYzhS8o3TrlqdBzRFCbOOn/4hbCXD/u3Q=";
  };

  npmDepsHash = "sha256-1H7z6y8czHF3Dewqqy5DA/RNeo2//J1eBYZqryX0MbU=";

  modelData = fetchzip {
    name = "pi-ai-model-data-${version}";
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha256-5Ss6xC3YH0MDbMDk//DqoePSOI8AIy2waVisCdTH+3U=";
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

    # Upstream's script builds every workspace in dependency order and
    # uses the bundled model data instead of the network.
    npm run build:offline

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
