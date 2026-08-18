{
  autoPatchelfHook,
  fetchFromGitHub,
  lib,
  makeWrapper,
  nodejs,
  python3,
  stdenv,
  yarn-berry_4,
  ...
}:

let
  yarn-berry = yarn-berry_4;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hedgedoc2";
  version = "2.0.0-alpha.3-unstable-2026-08-05";

  src = fetchFromGitHub {
    owner = "hedgedoc";
    repo = "hedgedoc";
    rev = "7a8280e5d850940ca4c7c0fb2d7f5e51ad5d91b8";
    hash = "sha256-gUVZp+IjpyTC6AV3VD/nNpKnV70MS9gZ771GLZAJrJM=";
  };

  patches = [ ./yarn-4.14.patch ];

  missingHashes = ./missing-hashes.json;
  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src patches missingHashes;
    hash = "sha256-GoNWRgQ8NLV371FcGJORB6x2viwGL6FCWbpgHbUY8bQ=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    (python3.withPackages (ps: [ ps.setuptools ]))
    yarn-berry
    yarn-berry.yarnBerryConfigHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = [
    nodejs
    stdenv.cc.cc.lib
  ];

  # sodium-native includes Android prebuilds that autoPatchelf also scans.
  autoPatchelfIgnoreMissingDeps = [ "libc++_shared.so" ];

  env = {
    CYPRESS_INSTALL_BINARY = "0";
    NEXT_TELEMETRY_DISABLED = "1";
    npm_config_nodedir = nodejs;
  };

  buildPhase = ''
    runHook preBuild

    yarn build \
      --filter=@hedgedoc/backend \
      --filter=@hedgedoc/frontend \
      --no-cache \
      --no-daemon

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    frontendRuntime="$TMPDIR/frontend-runtime"
    mkdir -p "$frontendRuntime"
    cp -R frontend/dist/. "$frontendRuntime/"

    yarn workspaces focus --production @hedgedoc/backend

    backendRoot="$out/share/hedgedoc2/backend"
    frontendRoot="$out/share/hedgedoc2/frontend"
    mkdir -p "$out/bin" "$backendRoot" "$frontendRoot"

    cp package.json "$backendRoot/package.json"
    cp -R node_modules "$backendRoot/node_modules"

    mkdir -p "$backendRoot/backend" "$backendRoot/database" "$backendRoot/commons"
    cp backend/package.json "$backendRoot/backend/package.json"
    cp -R backend/dist/src "$backendRoot/backend/dist"
    cp -R backend/public "$backendRoot/backend/public"
    cp database/package.json "$backendRoot/database/package.json"
    cp -R database/dist "$backendRoot/database/dist"
    cp commons/package.json "$backendRoot/commons/package.json"
    cp -R commons/dist "$backendRoot/commons/dist"

    cp -R "$frontendRuntime"/. "$frontendRoot/"

    makeWrapper ${nodejs}/bin/node "$out/bin/hedgedoc2-backend" \
      --add-flags "$backendRoot/backend/dist/main.js" \
      --chdir "$backendRoot/backend" \
      --set NODE_ENV production

    makeWrapper ${nodejs}/bin/node "$out/bin/hedgedoc2-frontend" \
      --add-flags "$frontendRoot/frontend/server.js" \
      --chdir "$frontendRoot/frontend" \
      --set NODE_ENV production \
      --set NEXT_TELEMETRY_DISABLED 1 \
      --set-default PORT 3001

    runHook postInstall
  '';

  meta = {
    description = "Realtime collaborative Markdown editor, HedgeDoc 2 development version";
    homepage = "https://hedgedoc.org";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
  };
})
