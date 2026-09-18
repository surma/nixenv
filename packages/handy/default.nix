{
  lib,
  stdenv,
  fetchurl,
  runCommand,
  appimageTools,
  undmg,
  alsa-lib,
  e2fsprogs,
  fontconfig,
  freetype,
  fribidi,
  gmp,
  harfbuzz,
  libdrm,
  libgbm,
  libglvnd,
  libgpg-error,
  libxcb,
  wayland,
  xkeyboard_config,
  xorg,
  zlib,
  ...
}:
let
  version = "0.9.6";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_aarch64.dmg";
      hash = "sha256-qWGzVyT2yGC83Ozh8dd8ITQ60hVlJfiADKlooarU2FQ=";
    };
    x86_64-linux = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.AppImage";
      hash = "sha256-xlL2lXLMhGMC12B2GYoHtNYrX3tUgoWTNSdYSjxi9P0=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-linux");

  # Libraries the prebuilt AppImage links against without bundling them.
  runtimeLibs = [
    alsa-lib
    e2fsprogs
    fontconfig.lib
    freetype
    fribidi
    gmp
    harfbuzz
    libdrm
    libgbm
    libglvnd
    libgpg-error
    libxcb
    stdenv.cc.cc.lib
    wayland
    xorg.libX11
    zlib
  ];

  meta = {
    description = "Speech-to-text tool";
    homepage = "https://github.com/cjpais/Handy";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };

  linuxMeta = {
    mainProgram = "handy";
  };

  handy-darwin = stdenv.mkDerivation rec {
    pname = "handy";
    inherit version meta;

    src = fetchurl source;

    nativeBuildInputs = [ undmg ];

    unpackPhase = ''
      runHook preUnpack;

      undmg ${src}
      rm Applications

      runHook postUnpack;
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -r "Handy.app" $out/Applications

      runHook postInstall
    '';
  };

  # The Linux build ships as an AppImage. The payload bundles most of its
  # libraries and finds them via $ORIGIN rpaths; the wrapper supplies the few
  # host libraries it does not bundle plus the xkb data, then hands over to
  # the AppImage's own AppRun so all APPDIR-relative paths stay intact.
  handy-linux =
    let
      extracted = appimageTools.extract {
        pname = "handy";
        inherit version;
        src = fetchurl source;
      };
    in
    runCommand "handy-${version}"
      {
        meta = meta // linuxMeta;
      }
      ''
        mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor

        cat > $out/bin/handy <<EOF
        #!/bin/sh
        APPDIR=${extracted}
        XKB_CONFIG_ROOT="${xkeyboard_config}/share/X11/xkb"
        LD_LIBRARY_PATH="${lib.makeLibraryPath runtimeLibs}:\$APPDIR/usr/lib\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        export APPDIR XKB_CONFIG_ROOT LD_LIBRARY_PATH
        exec "\$APPDIR/AppRun" "\$@"
        EOF
        chmod +x $out/bin/handy

        cp ${extracted}/usr/share/applications/Handy.desktop $out/share/applications/handy.desktop
        cp -r ${extracted}/usr/share/icons/hicolor/. $out/share/icons/hicolor/
      '';
in
if stdenv.isDarwin then handy-darwin else handy-linux
