{
  pkgs,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  name = "flacsplit";
  src = ./script.nu;
  dontUnpack = true;
  buildInputs = with pkgs; [
    nushell
    makeWrapper
  ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/flacsplit
    chmod +x $out/bin/*

    runHook postInstall
  '';
  fixupPhase = ''
    runHook preFixup;

    patchShebangs $out/bin/flacsplit
    wrapProgram $out/bin/flacsplit  \
    --set PATH ${
      lib.makeBinPath (
        with pkgs;
        [
          flac
          cuetools
          shntool
        ]
      )
    }

    runHook postFixup;
  '';
}
