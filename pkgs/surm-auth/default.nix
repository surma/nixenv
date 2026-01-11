{
  lib,
  buildGoModule,
  makeWrapper,
}:

buildGoModule rec {
  pname = "surm-auth";
  version = "0.1.0";

  # Source from local directory
  src = ../../apps/surm-auth;

  # Vendor hash - will be calculated on first build
  # This is a placeholder that will cause the build to fail with the correct hash
  vendorHash = null;

  # Include templates in the output
  postInstall = ''
    mkdir -p $out/share/surm-auth
    cp -r ${src}/templates $out/share/surm-auth/
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
