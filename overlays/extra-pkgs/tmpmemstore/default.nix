{ fetchFromGitHub, callPackage, ... }:
let
  tmpmemstoreSrc = fetchFromGitHub {
    owner = "surma";
    repo = "tmpmemstore";
    rev = "0fcb6dc98d5db3cc849f898f788fe084cb276cb2";
    hash = "sha256-7UTKWZeJGx5W+ZIUzoCvAUr7nfbqFbVEJ1tSBkCfI1I=";
  };
  tmpmemstore = callPackage (import tmpmemstoreSrc) { };
in
tmpmemstore
