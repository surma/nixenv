{ lib, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    {
      checks.surm-auth-e2e = pkgs.callPackage ../../modules/services/surmhosting/nix/checks/surm-auth-e2e.nix {
        inherit inputs;
        surm-auth = config.packages.surm-auth;
      };
    };
}
