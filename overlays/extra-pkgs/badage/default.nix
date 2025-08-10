{
  lib,
  rustPlatform,
  nix-gitignore,
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

  meta = with lib; {
    homepage = "https://github.com/surma/badage";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
