{ pkgs, config }:

config.boot.kernelPackages.v4l2loopback.overrideAttrs (oldAttrs: rec {
  version = "0.13.2";
  src = pkgs.fetchFromGitHub {
    owner = "umlaeute";
    repo = "v4l2loopback";
    rev = "v${version}";
    sha256 = "sha256-rcwgOXnhRPTmNKUppupfe/2qNUBDUqVb3TeDbrP5pnU=";
  };
})
