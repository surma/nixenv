{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  inherit (pkgs) callPackage writeShellApplication;
  app = callPackage (import ./app.nix) { };

  service = writeShellApplication {
    name = "service";
    text = ''
      set -a
      # shellcheck source=/dev/null
      source ${config.secrets.items.hate.target}
      ${app}/bin/hate
    '';
  };
in
{
  options = {
    services.hate.enable = mkEnableOption "";
  };
  config = lib.optionalAttrs (config.services.hate.enable) {
    secrets.items.hate.target = "/run/secrets/hate/env";
    systemd.services.hate = {
      enable = true;
      script = "${service}/bin/service";
      wantedBy = [ "multi-user.target" ];
    };
  };
}
