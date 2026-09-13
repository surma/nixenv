{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    {
      checks.surmhosting-module = (import ../../modules/services/surmhosting/tests { inherit pkgs; }).all;
      checks.surm-auth-e2e = pkgs.callPackage ../../modules/services/surmhosting/nix/checks/surm-auth-e2e.nix {
        surm-auth = config.packages.surm-auth;
      };
      checks.surmhosting-auth-container = lib.mkIf (pkgs.system == "x86_64-linux") (
        pkgs.callPackage ../../modules/services/surmhosting/tests/auth-container.nix { }
      );
    };
}
