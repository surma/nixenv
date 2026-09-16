{
  lib,
  stdenv,
  fetchurl,
  unzip,
  inputs,
  ...
}:

let
  version = "0.10.23";

  baseUrl = "https://github.com/abue-ammar/tinycast/releases/download/v${version}";

  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/Tinycast-${version}.zip";
      sha256 = "sha256-fs0uY0mRPamV1sFAIatrvgBj8SaeuplK2cnGa9vONwM=";
    };
    x86_64-darwin = {
      url = "${baseUrl}/Tinycast-Universal-${version}.zip";
      sha256 = "sha256-YAXj6effkl7FnXukd9WfsJnj2EJtpohMD+ZcOT4xI84=";
    };
  };

  # Get the source for current platform, or throw error if unsupported
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin.");

in
stdenv.mkDerivation rec {
  pname = "tinycast";
  inherit version;

  src = fetchurl {
    inherit (source) url sha256;
  };

  nativeBuildInputs = [ unzip ];

  # The fixup phase strips (and re-signs) Mach-O binaries under
  # `$out/Applications` by default, which breaks the vendor's code seal.
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack

    unzip ${src}

    runHook postUnpack;
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r "Tinycast.app" $out/Applications

    runHook postInstall
  '';

  meta = {
    description = "Native macOS launcher";
    homepage = "https://github.com/abue-ammar/tinycast";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
