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
    };
}
