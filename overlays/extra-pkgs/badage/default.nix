{ fetchFromGitHub, callPackage, ... }:
let
  badageSrc = fetchFromGitHub {
    owner = "surma";
    repo = "badage";
    rev = "d93258b499b2aa866042be5a5adc003df5199e76";
    hash = "sha256-q8WIfnNjGW6A642Ad0X87KMzZymq8M4EJdiTlp22jQI=";
  };
  badage = callPackage (import badageSrc) { };
in
badage
