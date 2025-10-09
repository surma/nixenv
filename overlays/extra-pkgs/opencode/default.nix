{
  system,
  stdenv,
  ...
}:
let
  version = "0.14.6";

  opencodeMeta = {
    "x86_64-linux" = {
      platform = "linux-x64";
      hash = "";
    };
    "aarch64-darwin" = {
      platform = "darwin-arm64";
      hash = "sha256:0whiz26dviymjxqrz37clnm3giijvy9mnm0qjqzyi7ppxzxhw2ag";
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
