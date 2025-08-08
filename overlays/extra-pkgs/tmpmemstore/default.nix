{ fetchFromGitHub, callPackage, ... }:
let
  tmpmemstoreSrc = fetchFromGitHub {
    owner = "surma";
    repo = "tmpmemstore";
    rev = "47980469499c50e809b75bf49e78484b61e0de68";
    hash = "sha256-ttAguaB/5flhFNJt2MuOqtGKSAhw2gCZsTZNt7U5H0s=";
  };
  tmpmemstore = callPackage (import tmpmemstoreSrc) { };
in
tmpmemstore
