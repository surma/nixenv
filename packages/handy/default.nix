{
  lib,
  fetchurl,
  undmg,
  stdenv,
  inputs,
  ...
}:
let
  version = "0.7.7";
  url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_aarch64.dmg";
  dmgFile = fetchurl {
    inherit url;
    hash = "sha256-rN/M7M8GxXI0RjNTsy6VmfKdczCa2Nvbu7KMAx80m2I=";
  };
in
stdenv.mkDerivation rec {
  pname = "handy";
  inherit version;

  src = dmgFile;

  nativeBuildInputs = [ undmg ];

  unpackPhase = ''
    runHook preUnpack;

    undmg ${src}
    rm Applications

    runHook postUnpack;
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r "Handy.app" $out/Applications

    runHook postInstall
  '';

  meta = {
    description = "Speech-to-text tool for macOS";
    homepage = "https://github.com/cjpais/Handy";
    platforms = lib.platforms.darwin;
  };
}
