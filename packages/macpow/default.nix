{
  lib,
  rustPlatform,
  fetchFromGitHub,
  ...
}:

rustPlatform.buildRustPackage rec {
  pname = "macpow";
  version = "0.1.17";

  src = fetchFromGitHub {
    owner = "k06a";
    repo = "macpow";
    rev = "v${version}";
    hash = "sha256-lIEjmafzc55uaFQa1mjJH466s10ckF2IW80i8g1Tl9I=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = {
    description = "Real-time power consumption monitor for Apple Silicon Macs";
    homepage = "https://github.com/k06a/macpow";
    license = lib.licenses.mit;
    mainProgram = "macpow";
    platforms = [ "aarch64-darwin" ];
  };
}
