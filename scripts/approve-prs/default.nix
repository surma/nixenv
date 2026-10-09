{
  lib,
  stdenv,
  makeWrapper,
  nushell,
  libnotify,
}:

stdenv.mkDerivation {
  name = "approve-prs";
  dontUnpack = true;

  buildInputs = [ nushell ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${./approve-prs.nu} $out/bin/approve-prs
    chmod +x $out/bin/approve-prs

    runHook postInstall
  '';

  # zsh and devx come from the inherited PATH.
  fixupPhase = ''
    runHook preFixup

    patchShebangs $out/bin/approve-prs
    wrapProgram $out/bin/approve-prs \
      --prefix PATH : ${lib.makeBinPath [ libnotify ]}

    runHook postFixup
  '';
}
