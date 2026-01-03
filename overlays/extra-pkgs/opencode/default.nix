{
  stdenv,
  lib,
  runCommand,
  curl,
  cacert,
  ...
}:
let
  version = "1.0.223";
  hash = "sha256-UF1vpx3DnjoJkybEn+d8oi+hB7m9HlB8xcV26p3aGUE=";

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
