{
  lib,
  buildGoModule,
  makeWrapper,
  tailscale,
  ...
}:
buildGoModule {
  pname = "tailscale-ips-update";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  # The tool shells out to `tailscale status --json`. Suffix rather than
  # prefix so a host with its own tailscale on PATH keeps using it.
  postFixup = ''
    wrapProgram $out/bin/tailscale-ips-update \
      --suffix PATH ":" ${lib.makeBinPath [ tailscale ]}
  '';

  meta = with lib; {
    description = "Refreshes the tailscale addresses in ips.nix from the live tailnet";
    license = licenses.mit;
    mainProgram = "tailscale-ips-update";
  };
}
