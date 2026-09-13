{
  lib,
  buildGoModule,
  makeWrapper,
  inputs,
  ...
}:
import ../../modules/services/surmhosting/nix/packages/surm-auth.nix {
  inherit lib buildGoModule makeWrapper inputs;
}
