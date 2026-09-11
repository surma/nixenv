{ lib, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    {
      checks.surm-auth-e2e = pkgs.callPackage ../../packages/surm-auth/e2e-check.nix {
        inherit inputs;
        surm-auth = config.packages.surm-auth;
      };
    };
}
