{
  system,
  stdenv,
  ...
}:
let
  version = "0.1.166";

  opencodeMeta = {
    "x86_64-linux" = {
      platform = "linux-x64";
      hash = "sha256:0im089zmb7ykx0yqv98djqw9kmn356am3qk67b32h5s7a99l3i8f";
    };
    "aarch64-darwin" = {
      platform = "darwin-arm64";
      hash = "sha256:12fsvpjk4mf4bhs258mwrf9jsff90fxxyjrwpp9yk8wx7ncafmfc";
    };
  };

  meta = opencodeMeta.${system};

  src = fetchTarball {
    url = "https://registry.npmjs.org/opencode-${meta.platform}/-/opencode-${meta.platform}-${version}.tgz";
    sha256 = meta.hash;
  };
in

stdenv.mkDerivation {
  pname = "opencode";
  inherit version src;

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out/
  '';
}
