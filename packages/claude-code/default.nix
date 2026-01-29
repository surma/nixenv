{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  inputs,
  ...
}:

let
  version = "2.1.23";

  # Base URL for all downloads
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # Platform-specific sources with SHA256 hashes from Homebrew cask
  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/${version}/darwin-arm64/claude";
      sha256 = "80e39bbc7cbbc7dea101dcf35676a270d5bff25a8a8e29ab038ceb131d8a7b3d";
    };
    x86_64-darwin = {
      url = "${baseUrl}/${version}/darwin-x64/claude";
      sha256 = "f22d8b1db63e631bd2a97ba14a0b924d9a8102d06efdc216228a42f93d665bbc";
    };
    x86_64-linux = {
      url = "${baseUrl}/${version}/linux-x64/claude";
      sha256 = "eff6d12c8220260b8d6926b35de20daae0db43de236920762c7da4c9d20dc843";
    };
    aarch64-linux = {
      url = "${baseUrl}/${version}/linux-arm64/claude";
      sha256 = "4b45afbb3ea3708ef6ed5038a7cc32054487f1fb577f56e9418b83d163f88f32";
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
