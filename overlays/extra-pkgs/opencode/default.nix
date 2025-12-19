{
  stdenv,
  lib,
  runCommand,
  curl,
  cacert,
  ...
}:
let
  version = "1.0.169";
  hash = "sha256-kU+CvUkuDLJfTQ+zufXpCiPTjepu80H8oMXz9gSs+lQ=";

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
