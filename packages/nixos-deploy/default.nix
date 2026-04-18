{
  lib,
  buildGoModule,
  inputs,
  ...
}:

buildGoModule {
  pname = "nixos-deploy";
  version = "0.1.0";

  src = inputs.self + "/apps/nixos-deploy";

  vendorHash = "sha256-snAjZ8SWi9VkdVptjyKc03mlPFTS179EMk1sjsHUMZQ=";

  env.CGO_ENABLED = 0;

  meta = with lib; {
    description = "Single-button web UI for triggering nixos-rebuild against a flake URL";
    homepage = "https://github.com/surma/nixenv";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "nixos-deploy";
  };
}
