{
  stdenv,
  lib,
  nushell,
  makeWrapper,
  age,
  openssh,
  git,
  coreutils,
  ...
}:
let
  script = ./secrets.nu;
in
stdenv.mkDerivation {
  name = "secrets";
  buildInputs = [
    nushell
  ];
  nativeBuildInputs = [
    makeWrapper
  ];
  src = script;
  dontUnpack = true;
  buildPhase = ''
    runHook preBuild

    mkdir -p $out/bin
    cp $src $out/bin/secrets

    patchShebangs $out/bin/secrets

    runHook postBuild
  '';
  postFixup = ''
    wrapProgram $out/bin/secrets \
     --prefix PATH ":" ${
       lib.makeBinPath [
         age
         openssh
         git
         coreutils
       ]
     }
  '';
}
