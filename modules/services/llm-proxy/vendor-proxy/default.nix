{ lib, buildGoModule }:

buildGoModule {
  pname = "vendor-proxy";
  version = "0.1.0";

  src = ./.;

  vendorHash = null;

  meta = with lib; {
    description = "Proxy service for Shopify vendor routes";
    license = licenses.mit;
    maintainers = [ ];
  };
}
