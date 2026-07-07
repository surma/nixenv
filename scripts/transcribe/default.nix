{
  lib,
  stdenv,
  makeWrapper,
  nushell,
  uv,
  ffmpeg,
}:

stdenv.mkDerivation {
  name = "transcribe";
  dontUnpack = true;

  buildInputs = [ nushell ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec
    cp ${./transcribe.py} $out/libexec/transcribe.py
    cp ${./transcribe.nu} $out/bin/transcribe
    chmod +x $out/bin/transcribe
    substituteInPlace $out/bin/transcribe --replace "@TRANSCRIBE_PY@" "$out/libexec/transcribe.py"

    runHook postInstall
  '';

  fixupPhase = ''
    runHook preFixup

    patchShebangs $out/bin/transcribe
    wrapProgram $out/bin/transcribe \
      --prefix PATH : ${
        lib.makeBinPath [
          uv
          ffmpeg
        ]
      }

    runHook postFixup
  '';
}
