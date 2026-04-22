{
  lib,
  buildGoModule,
  inputs,
  ...
}:

buildGoModule {
  pname = "nexus-admin";
  version = "0.2.0";

  src = inputs.self + "/apps/nexus-admin";

  vendorHash = "sha256-snAjZ8SWi9VkdVptjyKc03mlPFTS179EMk1sjsHUMZQ=";

  env.CGO_ENABLED = 0;

  meta = with lib; {
    description = "Web UI and REST API for NixOS deploys, journal logs, and unit management";
    homepage = "https://github.com/surma/nixenv";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "nexus-admin";
  };
}
