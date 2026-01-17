{
  pkgs,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  name = "timeout";
  src = ./script.sh;
  dontUnpack = true;
  buildInputs = with pkgs; [
    makeWrapper
  ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/timeout
    chmod +x $out/bin/timeout

    runHook postInstall
  '';
  fixupPhase = ''
    runHook preFixup

    substituteInPlace $out/bin/timeout \
      --replace "@coreutils@" "${pkgs.coreutils}"
    patchShebangs $out/bin/timeout

    runHook postFixup
  '';
}
