{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  glibc,
  inputs,
  ...
}:

let
  version = "2.1.118";

  # Base URL for all downloads
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # Platform-specific sources with SHA256 hashes from Homebrew cask
  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/${version}/darwin-arm64/claude";
      sha256 = "sha256-VOXT9lEJuJxgRvR0QJRNUpBsZi0eUXSPYgpDDSatNmU=";
    };
    x86_64-darwin = {
      url = "${baseUrl}/${version}/darwin-x64/claude";
      sha256 = "";
    };
    x86_64-linux = {
      url = "${baseUrl}/${version}/linux-x64/claude";
      sha256 = "sha256-cMH5iBt8CRxJ82lclMOB2cygrwlLy8mcufRj5E2Xzpw=";
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

  # On Linux, patch ONLY the ELF interpreter — not RPATH.
  # autoPatchelfHook must NOT be used here: it causes patchelf to reorganise the
  # ELF and silently truncate the 122 MB Bun standalone payload appended after
  # the ELF data, leaving a bare bun runtime that just prints bun's own help.
  # A targeted --set-interpreter patch preserves the payload intact.
  #
  # dontPatchELF / dontStrip: the stdenv fixupPhase would otherwise run
  # patchelf --shrink-rpath (and strip) on every ELF in $out, which also
  # truncates the payload for the same reason.
  nativeBuildInputs = lib.optionals stdenv.isLinux [ patchelf ];
  dontPatchELF = true;
  dontStrip = true;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src $out/bin/claude
    chmod +wx $out/bin/claude

    ${lib.optionalString stdenv.isLinux ''
      patchelf \
        --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 \
        $out/bin/claude
    ''}

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
