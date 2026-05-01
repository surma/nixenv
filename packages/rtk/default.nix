{
  lib,
  rustPlatform,
  fetchFromGitHub,
  ...
}:
rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.38.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-eINYlatbjpsqe46LNZIXvIrZEBf+QC3+2EjY7Ei7VZI=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  # No system deps: rusqlite uses the bundled feature, ureq uses rustls.
  doCheck = false;

  meta = {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    license = lib.licenses.mit;
    mainProgram = "rtk";
    platforms = lib.platforms.unix;
  };
}
