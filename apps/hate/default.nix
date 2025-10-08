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
      ${app}/bin/hate "$SERVER" "$TOKEN"
    '';
  };
in
{
  options = {
    services.hate.enable = mkEnableOption "";
  };
  config = {
    secrets.items.hate.target = "/run/secrets/hate-env";
    systemd.services.hate = lib.optionalAttrs (config.services.hate.enable) {
      enable = true;
      script = "${service}/bin/service";
      wantedBy = [ "multi-user.target" ];
      after = [ "secrets.service" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
