{ lib, buildGoModule }:

buildGoModule {
  pname = "vendor-proxy";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-iyhVyrAf3cVejT+balQdQiJy+CIdT00a/x1VOnhRj3I=";

  meta = with lib; {
    description = "Proxy service for Shopify vendor routes";
    license = licenses.mit;
    maintainers = [ ];
  };
}
