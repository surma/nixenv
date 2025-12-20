{
  pkgs,
  lib,
  ...
}:
with lib;
let
  inherit (pkgs) stdenv;
  version = "1.2.3";
  hash = "sha256:0sr0hg28aafd5lx8izq7ni25nmy7k18g9ppqp5x04a3f24gyjppk";

  src = builtins.fetchurl {
    url = "https://release.files.ghostty.org/${version}/Ghostty.dmg";
    sha256 = hash;
  };

  macPkg = stdenv.mkDerivation {
    name = "ghostty";
    inherit version src;

    meta.mainProgram = "ghostty";

    # FIXME: This is dirty!
    # The Ghostty DMG is APFS, not HFS+, which `undmg` does not suppport.
    # To be able to unpack it, I rely on the fact that builds on MacOS i
    # are not properly sandboxed and just use `hdiutil`.
    unpackPhase = ''
      runHook preUnpack

      mountpoint=$(mktemp -d)

      /usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mountpoint" $src

      cp -r "$mountpoint/Ghostty.app" .

      /usr/bin/hdiutil detach "$mountpoint"

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications $out/bin
      cp -r Ghostty.app $out/Applications/
      ln -sf $out/Applications/Ghostty.app/Contents/MacOS/ghostty $out/bin/ghostty

      runHook postInstall
    '';
  };
in
{
  imports = [
    ./default-config.nix
  ];
  config = {
    programs.ghostty.package = mkIf (stdenv.isDarwin) macPkg;
  };
}
