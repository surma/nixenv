{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule rec {
  pname = "rmapi";
  version = "0.0.35";

  src = fetchFromGitHub {
    owner = "ddvk";
    repo = "rmapi";
    rev = "v${version}";
    hash = "sha256-mRJH0fQ8e4igR7IwcJdvUhrZDXvpTt/Dac7Pc9p7ITw=";
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
