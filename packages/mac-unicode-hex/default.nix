{
  lib,
  stdenv,
  cmake,
  fcitx5,
  ...
}:

stdenv.mkDerivation {
  pname = "mac-unicode-hex";
  version = "1.0.0";

  src = lib.cleanSource ./src;

  nativeBuildInputs = [ cmake ];
  buildInputs = [ fcitx5 ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test-unicodehex
    runHook postCheck
  '';

  meta = {
    description = "macOS-style Unicode hex input for Fcitx5 via Right Alt";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
