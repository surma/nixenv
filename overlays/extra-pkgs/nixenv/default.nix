{
  stdenv,
  nushell,
  tmpmemstore,
}:
let
  script = ./nixenv;
in
stdenv.mkDerivation {
  name = "nixenv";
  buildInputs = [
    nushell
    tmpmemstore
  ];
  src = script;
  dontUnpack = true;
  buildPhase = ''
    runHook preBuild

    mkdir -p $out/bin
    cp $src $out/bin/nixenv

    patchShebangs $out/bin/nixenv

    runHook postBuild
  '';
}
