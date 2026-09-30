{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  perl,
  pkg-config,
  makeWrapper,
  makeRustPlatform,
  icnsify,
  rcodesign,
  inputs,
  alsa-lib,
  libGL,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  ...
}:
let
  revision = "76d07895a8aa5e4faaa0aa623262ddd6cefa7ecd"; # v0.17.0

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "zapfast";
    rev = revision;
    hash = "sha256-8ZdS8Y4YTjcOmAdDTSn2RSyf0NReYbsPIraNPV5doO4=";
  };

  # rust-toolchain.toml pins 1.98.0, newer than any rustc in this nixpkgs.
  # Fenix provides the exact toolchain from that file.
  fenix = inputs.fenix.packages.${stdenv.hostPlatform.system};

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
  # binary with the bundle assets from the fetched source.
  darwinBundle = ''
    app="$out/Applications/ZapFast.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

    cp "$out/bin/zapfast" "$app/Contents/MacOS/zapfast"
    chmod 755 "$app/Contents/MacOS/zapfast"

    sed "s/__VERSION__/${version}/g" "$src/packaging/macos/Info.plist" \
      > "$app/Contents/Info.plist"

    icnsify "$src/packaging/macos/icon-1024.png" \
      --output "$app/Contents/Resources/zapfast.icns"
  '';

  # Launchers such as wofi --show drun list XDG desktop entries, not bare
  # binaries, so install the entry and icon that upstream ships.
  linuxDesktopEntry = ''
    install -Dm644 "$src/packaging/applications/zapfast.desktop" \
      "$out/share/applications/zapfast.desktop"
    install -Dm644 "$src/packaging/icons/zapfast.svg" \
      "$out/share/icons/hicolor/scalable/apps/zapfast.svg"
  '';
in
rustPlatform.buildRustPackage {
  pname = "zapfast";
  inherit version;

  inherit src;

  cargoLock = {
    lockFile = src + "/Cargo.lock";
    # Git dependencies pinned in Cargo.lock; the vendored checkouts need
    # pinned hashes. Crates from the same repo revision share one hash.
    outputHashes = {
      "dpi-0.1.1" = "sha256-x93WYXGAA6SifvOrayIQtyc7N8jT+atScx/R1YRT06k=";
      "eframe-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "ecolor-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "egui-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "egui-wgpu-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "egui-winit-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "egui_extras-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "egui_glow-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "emath-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "epaint-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "epaint_default_fonts-0.36.1" = "sha256-uzNVqMeYdLI9jqvPxdsmOkJC17GiPWU0BpJ+aqDz5RM=";
      "fastframe-fonts-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-i18n-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-icons-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-log-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-macos-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-shell-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-text-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-theme-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-tray-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "fastframe-update-0.1.7" = "sha256-ZPpSX2j42BbBOu9W3VZ0H7mJKYgBLRoZ6MRWyEUj1bI=";
      "rodio-0.22.2" = "sha256-snwSU8P9iZeMSKJcX80FWl0IL32dCQqWGjNispeKlps=";
      "wacore-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "wacore-appstate-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "wacore-binary-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "wacore-derive-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "wacore-libsignal-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "wacore-noise-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "waproto-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "whatsapp-rust-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "whatsapp-rust-sqlite-storage-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "whatsapp-rust-tokio-transport-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "whatsapp-rust-ureq-http-client-0.7.0" = "sha256-+hV1XKntNGClwBUH5t06LSP3YpKJXnP2pmhNXKm2lU0=";
      "winit-0.30.13" = "sha256-x93WYXGAA6SifvOrayIQtyc7N8jT+atScx/R1YRT06k=";
    };
  };

  # opus builds libopus with cmake, the vendored SQLCipher OpenSSL needs perl.
  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    icnsify
    rcodesign
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ];

  # Linux libraries only; on Darwin the app links the system frameworks.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    libGL
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxrandr
  ];

  doCheck = false;

  # winit and glutin load these through dlopen at runtime (see
  # packaging/check-runtime-libs.c), so linking rpaths alone is not enough.
  # The final binary links with an empty RUNPATH, so the standard library
  # from the C++ toolchain (openh264) rides along too.
  postFixup =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapProgram "$out/bin/zapfast" \
        --prefix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath [
            stdenv.cc.cc.lib
            alsa-lib
            libGL
            wayland
            libxkbcommon
            libx11
            libxcursor
            libxi
            libxrandr
          ]
        }"
    ''
    # The Darwin signature must follow the generic strip hook.
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      rcodesign sign \
        --entitlements-xml-file "$src/packaging/macos/entitlements.plist" \
        "$out/Applications/ZapFast.app"
    '';

  postInstall =
    lib.optionalString stdenv.hostPlatform.isDarwin darwinBundle
    + lib.optionalString stdenv.hostPlatform.isLinux linuxDesktopEntry;

  meta = {
    description = "A native WhatsApp client built with Rust and egui";
    homepage = "https://zapfast.rocks";
    license = lib.licenses.mit;
    mainProgram = "zapfast";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
