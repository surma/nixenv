{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  perl,
  pkg-config,
  makeWrapper,
  makeRustPlatform,
  pkgs,
  alsa-lib,
  libGL,
  wayland,
  libxkbcommon,
  xorg,
  ...
}:
let
  revision = "2e8987bc954d8a3263ab1b519eef2df3a810d4bf";

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "zapfast";
    rev = revision;
    hash = "sha256-5GvR1f+XSpyxn1rW32ExWi6MW72kAnVHibwUS23+Fc4=";
  };

  # rust-toolchain.toml pins 1.98.0, newer than any rustc in this nixpkgs.
  # Fenix provides the exact toolchain from that file.
  fenix = import (builtins.fetchTarball {
    url = "https://github.com/nix-community/fenix/archive/f8ac2cd5626cc565f546e1053ab4591cfe0b3ea9.tar.gz";
    sha256 = "sha256-wt1Mee04mQYtOPolRGHbZFb3CyHKidFryurtWuOZOao=";
  }) { inherit pkgs; };

  toolchain = fenix.fromToolchainFile {
    file = src + "/rust-toolchain.toml";
    sha256 = "sha256-P30Tm3O7vQAE725YtDCDHGjNrSsfZO4us11UwJGZSJo=";
  };

  rustPlatform = makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };

  version = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"))).package.version;

  # Mirrors packaging/macos/bundle.sh: build ZapFast.app around the built
  # binary with the bundle assets from the fetched source. sips, iconutil,
  # and codesign come from the host's /usr/bin in the Darwin stdenv.
  darwinBundle = ''
    app="$out/Applications/ZapFast.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

    cp "$out/bin/zapfast" "$app/Contents/MacOS/zapfast"
    chmod 755 "$app/Contents/MacOS/zapfast"

    sed "s/__VERSION__/${version}/g" "$src/packaging/macos/Info.plist" \
      > "$app/Contents/Info.plist"

    iconset="$(mktemp -d)/zapfast.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
      sips -z $size $size "$src/packaging/macos/icon-1024.png" \
        --out "$iconset/icon_''${size}x''${size}.png" >/dev/null
      double=$((size * 2))
      sips -z $double $double "$src/packaging/macos/icon-1024.png" \
        --out "$iconset/icon_''${size}x''${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$app/Contents/Resources/zapfast.icns"

    codesign --force \
      --entitlements "$src/packaging/macos/entitlements.plist" --sign - "$app"
  '';
in
rustPlatform.buildRustPackage {
  pname = "zapfast";
  inherit version;

  inherit src;

  cargoLock = {
    lockFile = src + "/Cargo.lock";
    # whatsapp-rust is a git dependency pinned to a commit; the lockfile
    # names it, so the vendor step fetches it and needs a pinned hash.
    outputHashes = {
      "whatsapp-rust-0.7.0" = "sha256-BivXjeyjeRkZqMVpNF/pF2JY1dfA4m7+a/gOa2QPlEE=";
      "whatsapp-rust-sqlite-storage-0.7.0" = "sha256-BivXjeyjeRkZqMVpNF/pF2JY1dfA4m7+a/gOa2QPlEE=";
      "whatsapp-rust-tokio-transport-0.7.0" = "sha256-BivXjeyjeRkZqMVpNF/pF2JY1dfA4m7+a/gOa2QPlEE=";
      "whatsapp-rust-ureq-http-client-0.7.0" = "sha256-BivXjeyjeRkZqMVpNF/pF2JY1dfA4m7+a/gOa2QPlEE=";
    };
  };

  # opus builds libopus with cmake, the vendored SQLCipher OpenSSL needs perl.
  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ];

  # Linux libraries only; on Darwin the app links the system frameworks.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    libGL
    wayland
    libxkbcommon
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
  ];

  doCheck = false;

  # winit and glutin load these through dlopen at runtime (see
  # packaging/check-runtime-libs.c), so linking rpaths alone is not enough.
  # The final binary links with an empty RUNPATH, so the standard library
  # from the C++ toolchain (openh264) rides along too.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram "$out/bin/zapfast" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          stdenv.cc.cc.lib
          alsa-lib
          libGL
          wayland
          libxkbcommon
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
        ]
      }"
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin darwinBundle;

  meta = {
    description = "A native WhatsApp client built with Rust and egui";
    homepage = "https://zapfast.rocks";
    license = lib.licenses.mit;
    mainProgram = "zapfast";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
