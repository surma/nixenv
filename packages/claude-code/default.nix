{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  inputs,
  ...
}:

let
  version = "2.1.37";

  # Base URL for all downloads
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # Platform-specific sources with SHA256 hashes from Homebrew cask
  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/${version}/darwin-arm64/claude";
      sha256 = "sha256-AO0Qr7elYkQHc94xKEVozpwzOF1506kSoSryYq79Ew4=";
    };
    x86_64-darwin = {
      url = "${baseUrl}/${version}/darwin-x64/claude";
      sha256 = "";
    };
    x86_64-linux = {
      url = "${baseUrl}/${version}/linux-x64/claude";
      sha256 = "";
    };
    aarch64-linux = {
      url = "${baseUrl}/${version}/linux-arm64/claude";
      sha256 = "";
    };
  };

  # Get the source for current platform, or throw error if unsupported
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux");

in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    inherit (source) url sha256;
  };

  # Linux needs autoPatchelfHook to fix dynamic library paths
  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  # Don't try to unpack - it's a single executable binary
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/claude
    chmod +x $out/bin/claude

    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal-based AI coding assistant from Anthropic";
    homepage = "https://www.anthropic.com/claude-code";
    downloadPage = "https://www.anthropic.com/claude-code";
    mainProgram = "claude";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
