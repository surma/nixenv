{ lib, buildGoModule }:

buildGoModule {
  pname = "vendor-proxy";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-SAZpfeTKHC/OEgMUWScXYwx7RY6LrSHkHXLg4vArX+g=";

  meta = with lib; {
    description = "Proxy service for Shopify vendor routes";
    license = licenses.mit;
    maintainers = [ ];
  };
}
