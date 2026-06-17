{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule rec {
  pname = "rmapi";
  version = "0.0.34-unstable-2026-06-05";

  src = fetchFromGitHub {
    owner = "ddvk";
    repo = "rmapi";
    rev = "434da60d178dd04e0659fb502ea1251600c5d6ef";
    hash = "sha256-yRNYKsCzdmk9Oo5rsV7eH2bnmk1WlA7ahv3LL7BTSZU=";
  };

  vendorHash = "sha256-Qisfw+lCFZns13jRe9NskCaCKVj5bV1CV8WPpGBhKFc=";

  doCheck = false;

  meta = {
    description = "Go app that allows access to the reMarkable Cloud API programmatically";
    homepage = "https://github.com/ddvk/rmapi";
    license = lib.licenses.agpl3Only;
    mainProgram = "rmapi";
  };
}
