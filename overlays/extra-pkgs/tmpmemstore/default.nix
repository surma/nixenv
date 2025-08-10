{
  lib,
  rustPlatform,
  nix-gitignore,
  pkg-config,
  ...
}:

let
  src = nix-gitignore.gitignoreSource [ ] ./.;
  cargoToml = lib.importTOML "${src}/Cargo.toml";
in
rustPlatform.buildRustPackage rec {
  pname = cargoToml.package.name;
  version = cargoToml.package.version;

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  nativeBuildInputs = [ pkg-config ];
}
