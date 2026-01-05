{
  pkgs,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  name = "noti";
  src = ./script.nu;
  dontUnpack = true;
  buildInputs = with pkgs; [
    nushell
    makeWrapper
  ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/noti
    chmod +x $out/bin/*

    runHook postInstall
  '';
  fixupPhase = ''
    runHook preFixup

    patchShebangs $out/bin/noti
    wrapProgram $out/bin/noti \
      --set PATH ${lib.makeBinPath (with pkgs; lib.optionals stdenv.isLinux [ libnotify ])}

    runHook postFixup
  '';
}
