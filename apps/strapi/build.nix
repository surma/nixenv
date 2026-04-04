{
  lib,
  buildNpmPackage,
  importNpmLock,
  nodejs_22,
  python3,
  pkg-config,
  sqlite,
  makeWrapper,
}:
let
  src = ./.;
  packageJson = lib.importJSON "${src}/package.json";
in
buildNpmPackage {
  pname = packageJson.name;
  version = packageJson.version;

  inherit src;

  nodejs = nodejs_22;

  nativeBuildInputs = [
    python3
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    sqlite
  ];

  npmDeps = importNpmLock { npmRoot = src; };
  npmConfigHook = importNpmLock.npmConfigHook;

  # Strapi needs to build its admin panel
  npmBuildScript = "build";

  doCheck = false;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/strapi
    cp -r . $out/lib/strapi

    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/strapi \
      --add-flags "$out/lib/strapi/node_modules/.bin/strapi"

    runHook postInstall
  '';
}
