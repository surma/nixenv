{
  pkgs,
  lib,
  stdenv,
  defaultMobileDevice ? null,
  homeassistantCli ? pkgs.callPackage ../homeassistant-cli { },
  ...
}:
let
  runtimePath =
    [ homeassistantCli ]
    ++ lib.optional stdenv.isLinux pkgs.libnotify;
in
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
      --prefix PATH : ${lib.makeBinPath runtimePath} \
      ${lib.optionalString (
        defaultMobileDevice != null
      ) "--set NOTI_MOBILE_DEVICE ${lib.escapeShellArg defaultMobileDevice}"}

    runHook postFixup
  '';
}
