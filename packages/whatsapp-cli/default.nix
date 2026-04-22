{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
let
  version = "1.3.3-patched";
in
buildGoModule {
  pname = "whatsapp-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "vicentereig";
    repo = "whatsapp-cli";
    tag = "v1.3.3";
    hash = "sha256-jV/JvCY7eSCPaKK3icoUWRjBy793NaPSbM8KUkpYdZQ=";
  };

  patches = [
    # Bump whatsmeow to v0.0.0-20260421083005 (April 21, 2026)
    # to pick up the latest client version number required by WhatsApp.
    # Drop this patch once upstream releases a version with the bump.
    ./bump-whatsmeow.patch
  ];

  vendorHash = "sha256-UCeuD5R7Foci8rKu4hbUMz8HmOt8DPAwDv+nH1M2Hxk=";

  env.CGO_ENABLED = "1";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Command-line interface for WhatsApp built on the WhatsApp Web multidevice protocol";
    homepage = "https://github.com/vicentereig/whatsapp-cli";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "whatsapp-cli";
  };
}
