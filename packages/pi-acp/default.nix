{
  buildNpmPackage,
  fetchurl,
  importNpmLock,
  lib,
  makeWrapper,
  nodejs_22,
  ...
}:
let
  version = "0.0.26";
in
buildNpmPackage {
  pname = "pi-acp";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-acp/-/pi-acp-${version}.tgz";
    hash = "sha256-45ebEgihAxcrYcCv0eyLz6IST8IWK+PrBeGhzy0+nwE=";
  };
  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper ];

  npmDeps = importNpmLock {
    npmRoot = ./.;
  };
  npmConfigHook = importNpmLock.npmConfigHook;

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/pi-acp $out/bin
    cp -r dist package.json package-lock.json node_modules $out/lib/node_modules/pi-acp/

    makeWrapper ${nodejs_22}/bin/node $out/bin/pi-acp \
      --add-flags $out/lib/node_modules/pi-acp/dist/index.js

    runHook postInstall
  '';

  meta = {
    description = "ACP adapter for pi coding agent";
    homepage = "https://github.com/svkozak/pi-acp";
    downloadPage = "https://www.npmjs.com/package/pi-acp";
    license = lib.licenses.mit;
    mainProgram = "pi-acp";
  };
}
