{
  stdenv,
  lib,
  nushell,
  makeWrapper,
  nix,
  git,
  coreutils,
  ...
}:
let
  script = ./update-all.nu;
in
stdenv.mkDerivation {
  name = "update-all";

  buildInputs = [ nushell ];
  nativeBuildInputs = [ makeWrapper ];

  src = script;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p $out/bin
    cp $src $out/bin/update-all

    patchShebangs $out/bin/update-all

    runHook postBuild
  '';

  postFixup = ''
    wrapProgram $out/bin/update-all \
      --prefix PATH ":" ${
        lib.makeBinPath [
          nix
          git
          coreutils
        ]
      }
  '';
}
