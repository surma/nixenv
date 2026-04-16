{
  inputs,
  stdenv,
  lib,
  ...
}:
let
  unstableBun = inputs.nixpkgs-unstable.legacyPackages.${stdenv.hostPlatform.system}.bun;
in
inputs.opencode.packages.${stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./relax-bun-version-check.patch ];
  nativeBuildInputs = [ unstableBun ] ++ lib.filter (pkg: (pkg.pname or "") != "bun") (old.nativeBuildInputs or [ ]);
})
