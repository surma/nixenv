{ lib, buildGoModule }:

buildGoModule {
  pname = "llm-vendor-proxy";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-SAZpfeTKHC/OEgMUWScXYwx7RY6LrSHkHXLg4vArX+g=";

  meta = with lib; {
    description = "Reverse proxy for Shopify vendor API endpoints with authentication";
    license = licenses.mit;
    maintainers = [ ];
  };
}
