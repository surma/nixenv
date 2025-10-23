{
  stdenv,
  lib,
  runCommand,
  curl,
  cacert,
  ...
}:
let
  version = "0.15.14";
  hash = "sha256-7r+TLmhrz/pzLD6xEdmMDiARSKU5/X2fdoRmwvlYWDY=";

  platforms = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "aarch64-darwin" = "darwin-arm64";
  };

  urls =
    platforms
    |> lib.attrsToList
    |> map (
      { name, value }:
      ''
        mkdir -p "$out/${name}"
        curl "https://registry.npmjs.org/opencode-${value}/-/opencode-${value}-${version}.tgz" | tar -xzf - -C "$out/${name}"
      ''
    );

  srcs =
    runCommand "opencode-binaries"
      {
        nativeBuildInputs = [
          curl
          cacert
        ];
        outputHash = hash;
        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
      }
      ''
        ${urls |> lib.concatLines}
      '';
in
runCommand "opencode" { } ''
  mkdir -p $out/bin
  ln -sf ${srcs}/${stdenv.system}/package/bin/opencode $out/bin/opencode
''
