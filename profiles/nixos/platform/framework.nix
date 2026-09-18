{ ... }:
# Fixes that every Framework laptop needs, regardless of model. The machine
# still imports its own `inputs.nixos-hardware.nixosModules.framework-*`
# module, because that one names the exact model.
{
  imports = [
    ../../../modules/nixos/framework/suspend-fix.nix
    ../../../modules/nixos/framework/wifi-fix.nix
  ];
}
