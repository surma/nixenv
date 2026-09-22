{
  lib,
  buildGoModule,
  makeWrapper,
  tailscale,
  ...
}:
buildGoModule {
  pname = "tailscale-cf-dns";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  # Only the optional drift check calls the tailscale CLI. A missing binary
  # downgrades to a log line, so this is a convenience, not a requirement.
  postFixup = ''
    wrapProgram $out/bin/tailscale-cf-dns \
      --suffix PATH ":" ${lib.makeBinPath [ tailscale ]}
  '';

  meta = with lib; {
    description = "Converges Cloudflare DNS records for tailnet hosts to ips.nix";
    license = licenses.mit;
    mainProgram = "tailscale-cf-dns";
  };
}
