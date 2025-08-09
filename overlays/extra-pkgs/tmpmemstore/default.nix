{ fetchFromGitHub, callPackage, ... }:
let
  tmpmemstoreSrc = fetchFromGitHub {
    owner = "surma";
    repo = "tmpmemstore";
    rev = "574fa61300cdecf7b393dddf4987b324957d9ff";
    hash = "sha256-JjbKOnTLoqm2+XIiL7xnmFitxXGPlEi60c3ULSYHP5M=";
  };
  tmpmemstore = callPackage (import tmpmemstoreSrc) { };
in
tmpmemstore
