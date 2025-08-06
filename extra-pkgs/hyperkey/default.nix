{
  lib,
  fetchurl,
  undmg,
  stdenv,
}:
let
  version = "0.50";
  url = "https://hyperkey.app/downloads/Hyperkey${version}.dmg";
  dmgFile = fetchurl {
    inherit url;
    hash = "sha256-xTbqwrbyDxD6TfbRzED/ISvyuqJlx8Csn97d06uqc9c=";
  };
in
stdenv.mkDerivation rec {
  pname = "hyperkey";
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
    cp -r "Hyperkey.app" $out/Applications

    runHook postInstall
  '';

  meta = {
    description = "The extra macOS modifier key";
    homepage = "https://hyperkey.app/";
    downloadPage = "https://hyperkey.app/";
    # license = lib.licenses.mit;
    # maintainers = [ ];
    platforms = lib.platforms.darwin;
    mainProgram = "hyperkey";
    unfree = true;
  };
}
