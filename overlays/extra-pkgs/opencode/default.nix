{
  system,
  stdenv,
  ...
}:
let
  version = "0.15.1";

  opencodeMeta = {
    "x86_64-linux" = {
      platform = "linux-x64";
      hash = "";
    };
    "aarch64-darwin" = {
      platform = "darwin-arm64";
      hash = "sha256:1avh01zbrzzd6fvca7jliiadbjjy26yzr91khv8hzfn2bsas8rr1";
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
