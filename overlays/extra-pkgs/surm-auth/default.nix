{
  lib,
  buildGoModule,
  makeWrapper,
  inputs,
  ...
}:

buildGoModule rec {
  pname = "surm-auth";
  version = "0.1.0";

  # Source from apps directory in the flake
  src = inputs.self + "/apps/surm-auth";

  # Vendor hash calculated from go.mod/go.sum
  vendorHash = "sha256-+SRUX9Vqifp30pPq1qg8vvA0mHMi7gAGrJatdUMVDRA=";

  # Include templates in the output
  postInstall = ''
    mkdir -p $out/share/surm-auth
    cp -r $src/templates $out/share/surm-auth/
  '';

  # Wrap binary to set template path
  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/surm-auth \
      --set SURM_AUTH_TEMPLATES $out/share/surm-auth/templates
  '';

  meta = with lib; {
    description = "Simple OAuth2 authentication service for surmhosting";
    homepage = "https://github.com/surma/nixenv";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "surm-auth";
  };
}
