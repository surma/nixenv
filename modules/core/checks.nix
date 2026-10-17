{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        # Evaluation check of the nexus.apps module with sample apps.
        nexus-apps = import ../services/nexus-apps/test.nix {
          inherit pkgs;
          inherit (inputs) surmhosting;
        };
        # NixOS VM test of the throwaway containers service.
        throwaway-containers = import ../services/throwaway-containers/test.nix {
          inherit pkgs;
          inherit (inputs) surmhosting;
        };
      };
    };
}
