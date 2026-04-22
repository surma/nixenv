{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  protobuf,
  cmake,
  ...
}:
let
  version = "0.7.0-post1";
  rev = "600c4ede51865f7de6ca21507e738a7bd70cc7ae";
in
rustPlatform.buildRustPackage {
  pname = "presage-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "whisperfish";
    repo = "presage";
    inherit rev;
    hash = "sha256-Z1tC1Wot+8Mv/jSGHwdw4GeNo2hkasfPYidhcuOn1Ww=";
  };

  patches = [
    # Fix clap ArgGroup referencing non-existent "recipient_uuid"
    # instead of the actual field name "recipient_service_id".
    # Without this, `list-messages` panics on startup.
    ./fix-list-messages-arg.patch
  ];

  cargoHash = "sha256-NZzNYK9iaMuacOsS10o3iUuElIXlN80U61ANwb2DdJQ=";

  nativeBuildInputs = [
    pkg-config
    protobuf
    cmake
  ];

  buildInputs = [
    openssl
  ];

  cargoBuildFlags = [ "-p" "presage-cli" ];
  cargoTestFlags = [ "-p" "presage-cli" ];

  meta = {
    description = "Signal Messenger CLI built on presage, a Rust library for Signal";
    homepage = "https://github.com/whisperfish/presage";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "presage-cli";
  };
}
