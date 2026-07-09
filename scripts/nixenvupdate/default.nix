{
  coreutils,
  lib,
  makeWrapper,
  nushell,
  stdenv,
}:

stdenv.mkDerivation {
  name = "nixenvupdate";
  src = ./script.nu;
  dontUnpack = true;

  buildInputs = [ nushell ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/nixenvupdate
    chmod +x $out/bin/nixenvupdate

    runHook postInstall
  '';

  fixupPhase = ''
    runHook preFixup

    patchShebangs $out/bin/nixenvupdate
    wrapProgram $out/bin/nixenvupdate \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}

    runHook postFixup
  '';
}
