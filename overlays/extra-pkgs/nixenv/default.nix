{
  stdenv,
  nushell,
}:
let
  script = ./nixenv;
in
stdenv.mkDerivation {
  name = "nixenv";
  buildInputs = [ nushell ];
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
