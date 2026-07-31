{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  buildNpmPackage,
  cmake,
  pkg-config,
  makeWrapper,
  boost,
  curl,
  miniupnpc,
  nlohmann_json,
  openssl,
  libopus,
  apple-sdk_15,
  darwinMinVersionHook,
  ...
}:
let
  revision = "5c3bd0f4109eb4069d10ee1a8201b9bf3a328018";
  ffmpegPrepared = fetchzip {
    url = "https://github.com/LizardByte/build-deps/releases/download/v2026.209.233149/Darwin-arm64-ffmpeg.tar.gz";
    hash = "sha256-SSr7TmfzLaFNaI+qO4B1oYPCyD/ysrFDqa931Bjfg2g=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "lumen";
  version = "0.0.0-unstable-2026-02-16";

  src = fetchFromGitHub {
    owner = "trollzem";
    repo = "Lumen";
    rev = revision;
    hash = "sha256-+vzWBYrXMompedxNKtAaf+KIEdWR+bo1x/ZAtlYmUDw=";
  };

  patches = [ ./nix-build.patch ];

  ui = buildNpmPackage {
    pname = "lumen-ui";
    inherit (finalAttrs) src version patches;
    npmDepsHash = "sha256-9Yvfxg71Mwck6koZcMLoq5mhsgs7Y4/4V1XwQ00eia4=";

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R build "$out/"

      runHook postInstall
    '';
  };

  postPatch = ''
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' ""

    echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    boost
    curl
    miniupnpc
    nlohmann_json
    openssl
    libopus
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
    (darwinMinVersionHook "14.0")
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeBool "BUILD_TESTS" false)
    (lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegPrepared}")
    (lib.cmakeFeature "CMAKE_CXX_STANDARD" "23")
    (lib.cmakeFeature "OPENSSL_INCLUDE_DIR" "${openssl.dev}/include")
    (lib.cmakeFeature "OPENSSL_CRYPTO_LIBRARY" "${openssl.out}/lib/libcrypto.dylib")
    (lib.cmakeFeature "OPENSSL_SSL_LIBRARY" "${openssl.out}/lib/libssl.dylib")
    (lib.cmakeFeature "SUNSHINE_ASSETS_DIR" "assets")
    (lib.cmakeFeature "SUNSHINE_ASSETS_DIR_DEF" "assets")
    (lib.cmakeBool "SUNSHINE_BUILD_HOMEBREW" false)
  ];

  env = {
    BUILD_VERSION = "0.0.0";
    BRANCH = "master";
    COMMIT = revision;
    MACOSX_DEPLOYMENT_TARGET = "14.0";
    NIX_OUTPATH_USED_AS_RANDOM_SEED = revision;
  };

  preConfigure = ''
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -ffile-prefix-map=$NIX_BUILD_TOP=/build"
  '';

  preBuild = ''
    cp -R ${finalAttrs.ui}/build ../
  '';

  buildFlags = [
    "sunshine"
    "vd_helper"
  ];

  postBuild = lib.optionalString stdenv.hostPlatform.isDarwin ''
    $CC -framework CoreGraphics \
      ../src/platform/macos/get_display_origin.m \
      -o get_display_origin
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/lumen/assets"
    install -m755 sunshine vd_helper "$out/libexec/lumen/"
    install -m755 get_display_origin "$out/bin/"
    cp -R assets/. "$out/libexec/lumen/assets/"

    makeWrapper "$out/libexec/lumen/sunshine" "$out/bin/sunshine" \
      --chdir "$out/libexec/lumen"
    ln -s sunshine "$out/bin/lumen"
    ln -s ../libexec/lumen/vd_helper "$out/bin/vd_helper"

    runHook postInstall
  '';

  meta = {
    description = "Native macOS game streaming host based on Sunshine";
    homepage = "https://github.com/trollzem/Lumen";
    license = lib.licenses.gpl3Only;
    mainProgram = "lumen";
    platforms = [ "aarch64-darwin" ];
  };
})
