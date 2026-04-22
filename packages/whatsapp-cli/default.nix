{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
let
  version = "0.2.1-patched";
in
buildGoModule {
  pname = "whatsapp-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "eddmann";
    repo = "whatsapp-cli";
    tag = "v0.2.1";
    hash = "sha256-KB27T0sRDU2DidLs0ZhWWvAXq0ucSa3+4F77aWbjiyw=";
  };

  patches = [
    # Bump whatsmeow to v0.0.0-20260421083005 (April 21, 2026)
    # to pick up the latest client version number required by WhatsApp.
    # Drop this patch once upstream releases a version with the bump.
    ./eddmann-bump-whatsmeow.patch
    # Enable full history sync (RequireFullSync=true), on-demand backfill
    # (OnDemandReady + CompleteOnDemandReady), and implement the backfill
    # command which was a no-op upstream.
    ./full-sync-and-backfill.patch
  ];

  vendorHash = "sha256-eaGJ8MEVctO0+i5POj9Z4HjfzaH2PCCOHG78qSKOksk=";

  env.CGO_ENABLED = "1";
  tags = [ "sqlite_fts5" ];
  subPackages = [ "cmd/whatsapp" ];

  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    mv $out/bin/whatsapp $out/bin/whatsapp-cli
  '';

  meta = {
    description = "WhatsApp from your terminal — pipe it, script it, automate it";
    homepage = "https://github.com/eddmann/whatsapp-cli";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "whatsapp-cli";
  };
}
