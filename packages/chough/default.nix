{
  lib,
  buildGoModule,
  go_1_26,
  fetchFromGitHub,
  ffmpeg,
  makeWrapper,
  patchelf,
  stdenv,
  autoPatchelfHook,
  inputs,
  ...
}:
let
  version = "1.0.0";
  buildGoModule126 = buildGoModule.override { go = go_1_26; };
in
buildGoModule126 {
  pname = "chough";
  inherit version;

  src = fetchFromGitHub {
    owner = "hyperpuncher";
    repo = "chough";
    tag = "v${version}";
    hash = "sha256-MMfkgsxe2dJbuUNoKR+fVeFHEVABCIR14lWrFLNA+Sw=";
  };

  vendorHash = "sha256-P1F6s33RD3TNP+EA1I7BFSgqLzPgVufuosJrNa8UMjQ=";
  proxyVendor = true;

  env.CGO_ENABLED = "1";

  subPackages = [ "cmd/chough" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    patchelf
  ];

  # Provide libstdc++ and libgcc_s for the pre-built sherpa-onnx .so files.
  buildInputs = [
    stdenv.cc.cc.lib
  ];

  # The sherpa-onnx .so files are bundled in the Go module and self-contained
  # (they only depend on glibc/libstdc++). We handle their RPATH ourselves.
  autoPatchelfIgnoreMissingDeps = [
    "libsherpa-onnx-c-api.so"
    "libsherpa-onnx-cxx-api.so"
    "libonnxruntime.so"
  ];

  # Copy bundled .so files and fix RPATH before fixupPhase checks for /build/ refs.
  postInstall = ''
    mkdir -p $out/lib

    # sherpa-onnx-go-linux bundles pre-built .so for each arch
    local sherpa_lib="$GOPATH/pkg/mod/github.com/k2-fsa/sherpa-onnx-go-linux@v1.12.28/lib/x86_64-unknown-linux-gnu"
    cp "$sherpa_lib"/libsherpa-onnx-c-api.so "$out/lib/"
    cp "$sherpa_lib"/libsherpa-onnx-cxx-api.so "$out/lib/"
    cp "$sherpa_lib"/libonnxruntime.so "$out/lib/"

    patchelf --set-rpath "$out/lib" "$out/bin/chough"
  '';

  postFixup = ''
    # Fix RPATH on the unwrapped binary (makeWrapper renames it)
    if [ -f "$out/bin/.chough-wrapped" ]; then
      patchelf --set-rpath "$out/lib" "$out/bin/.chough-wrapped"
    fi
    wrapProgram $out/bin/chough \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}
  '';

  meta = {
    description = "Fast speech-to-text CLI using NVIDIA Parakeet via sherpa-onnx";
    homepage = "https://github.com/hyperpuncher/chough";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "chough";
  };
}
